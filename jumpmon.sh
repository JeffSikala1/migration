#!/usr/bin/env bash
# jumpmon.sh - log per-user memory (PSS), process/thread counts and headroom on the jump box,
# so the next incident can be attributed to a user/process. Run as root (needs /proc/*/smaps_rollup).
#
#   sudo ./jumpmon.sh once                # one snapshot to the terminal
#   sudo ./jumpmon.sh loop [seconds]      # append a snapshot every N seconds (default 60) to the log
#
# Log: /var/log/jumpmon/snap.log (override with JUMPMON_LOG). Rotated to .1 at ~50 MB (JUMPMON_MAXKB).

set -u
LOG="${JUMPMON_LOG:-/var/log/jumpmon/snap.log}"
MAXKB="${JUMPMON_MAXKB:-51200}"

snap() {
  echo "=== $(date -u +%FT%TZ)  load: $(cut -d' ' -f1-3 /proc/loadavg)  tasks: $(ps -eLf --no-headers | wc -l)"
  awk '/^(MemTotal|MemAvailable|Shmem|Slab|PageTables|SwapFree):/ {printf "%s %.0fMB  ", $1, $2/1024} END {print ""}' /proc/meminfo
  [ -r /proc/pressure/memory ] && echo "PSI memory: $(head -1 /proc/pressure/memory)"
  echo "-- per-uid: PSS MB / procs / threads (PSS counts shared pages fairly)"
  # getline from a vanished/unreadable file just returns -1, so exiting processes cannot abort this
  awk '
    { u=$2; np[u]++; nt[u]+=$3; f="/proc/" $1 "/smaps_rollup"
      while ((getline line < f) > 0) if (line ~ /^Pss:/) { split(line, b, " "); pss[u] += b[2] }
      close(f) }
    END { for (u in np) printf "%8.0f MB %5d procs %6d thr  uid %s\n", pss[u]/1024, np[u], nt[u], u }
  ' <(ps -eo pid=,uid=,nlwp=) 2>/dev/null | sort -rn | head -10
  echo "-- top processes by RSS"
  ps -eo pid=,uid=,rss=,nlwp=,etime=,args= --sort=-rss | head -8 | cut -c1-160
  echo
}

rotate() {
  [ -f "$LOG" ] || return 0
  local kb; kb=$(du -k "$LOG" | cut -f1)
  [ "$kb" -gt "$MAXKB" ] && mv -f "$LOG" "$LOG.1"
}

case "${1:-once}" in
  once) snap ;;
  loop)
    INT="${2:-60}"
    mkdir -p "$(dirname "$LOG")"
    while true; do snap >> "$LOG" 2>&1; rotate; sleep "$INT"; done ;;
  *) echo "usage: $0 once | loop [seconds]"; exit 1 ;;
esac