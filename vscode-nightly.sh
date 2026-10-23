#!/usr/bin/env bash

# anything running in a VS Code terminal that is NOT inside tmux/screen will be stopped. 
set -u
ME="$(id -un)"
LOG="${VSCODE_NIGHTLY_LOG:-$HOME/vscode-nightly.log}"
STALE_DAYS="${VSCODE_STALE_DAYS:-7}"      # logs older than this are removed
KEEP_VERSIONS="${VSCODE_KEEP_VERSIONS:-3}" # newest server versions to keep, however old (folder dates are NOT last-use)
PATTERN='\.vscode-server|/vscode-server/|server-main\.js'
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
 
# this script and everything that launched it (shell, cron, a wrapper) must never be killed
ancestors() { local p=$$; while [ -n "$p" ] && [ "$p" -gt 1 ]; do echo "$p"; p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; done; }
mine()   { pgrep -u "$ME" -f "$PATTERN" | grep -vxFf <(ancestors); }
count()  { mine | wc -l; }
rss_mb() { ps -u "$ME" -o rss=,args= | grep -E "$PATTERN" | grep -v grep | awk '{s+=$1} END {printf "%.0f", s/1024}'; }
stamp()  { date '+%F %T'; }
# every version folder except the newest $KEEP_VERSIONS (by folder date)
old_versions() {
  ls -1dt "$HOME"/.vscode-server/cli/servers/Stable-* "$HOME"/.vscode-server/bin/* 2>/dev/null | tail -n +"$((KEEP_VERSIONS + 1))"
}
 
before_n="$(count)"; before_mb="$(rss_mb)"
 
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] $ME: $before_n VS Code server processes, ${before_mb:-0} MB RSS"
  mine | head -20 | xargs -r ps -o pid=,etime=,rss=,args= -p | cut -c1-150
  echo "[dry-run] would remove in /tmp: $(find /tmp -maxdepth 1 -user "$ME" -name 'code-*' 2>/dev/null | wc -l) socket/temp entries"
  echo "[dry-run] would remove all but the newest $KEEP_VERSIONS server versions:"
  old_versions | sed 's/^/  /'
  echo "[dry-run] would remove logs older than $STALE_DAYS days:"
  find -H "$HOME/.vscode-server/data/logs" -maxdepth 1 -mindepth 1 -mtime +"$STALE_DAYS" 2>/dev/null
  exit 0
fi
 
# 1) stop my VS Code server tree: polite first, force after 5 seconds
pids="$(mine)"
[ -n "$pids" ] && kill -TERM $pids 2>/dev/null
sleep 5
pids="$(mine)"
[ -n "$pids" ] && kill -KILL $pids 2>/dev/null
 
# 2) remove my leftover sockets/temp files
find /tmp -maxdepth 1 -user "$ME" -name 'code-*' -exec rm -rf {} + 2>/dev/null
 
# 3) keep the newest N server versions, remove older ones; remove old logs
old_versions | xargs -r rm -rf
find -H "$HOME/.vscode-server/data/logs" -maxdepth 1 -mindepth 1 -mtime +"$STALE_DAYS" -exec rm -rf {} + 2>/dev/null
 
after_n="$(count)"
echo "$(stamp) $ME  before: ${before_n} procs / ${before_mb:-0} MB   after: ${after_n} procs" >> "$LOG"
# keep the log short
tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
 