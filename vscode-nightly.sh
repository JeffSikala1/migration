#!/usr/bin/env bash

# anything running in a VS Code terminal that is NOT inside tmux/screen will be stopped.

set -u
ME="$(id -un)"
LOG="${VSCODE_NIGHTLY_LOG:-$HOME/vscode-nightly.log}"
STALE_DAYS="${VSCODE_STALE_DAYS:-7}"      # old server versions/logs older than this are removed
PATTERN='\.vscode-server|/vscode-server/|server-main\.js'
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

mine()   { pgrep -u "$ME" -f "$PATTERN" | grep -vx "$$"; }
count()  { mine | wc -l; }
rss_mb() { ps -u "$ME" -o rss=,args= | grep -E "$PATTERN" | grep -v grep | awk '{s+=$1} END {printf "%.0f", s/1024}'; }
stamp()  { date '+%F %T'; }

before_n="$(count)"; before_mb="$(rss_mb)"

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] $ME: $before_n VS Code server processes, ${before_mb:-0} MB RSS"
  mine | head -20 | xargs -r ps -o pid=,etime=,rss=,args= -p | cut -c1-150
  echo "[dry-run] would remove in /tmp: $(find /tmp -maxdepth 1 -user "$ME" -name 'code-*' 2>/dev/null | wc -l) socket/temp entries"
  echo "[dry-run] would remove server versions/logs older than $STALE_DAYS days:"
  find -H "$HOME/.vscode-server/cli/servers" "$HOME/.vscode-server/bin" -maxdepth 1 -mindepth 1 -mtime +"$STALE_DAYS" 2>/dev/null
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

# 3) remove old server versions and logs (keeps anything touched in the last N days)
find -H "$HOME/.vscode-server/cli/servers" "$HOME/.vscode-server/bin" -maxdepth 1 -mindepth 1 -mtime +"$STALE_DAYS" -exec rm -rf {} + 2>/dev/null
find -H "$HOME/.vscode-server/data/logs" -maxdepth 1 -mindepth 1 -mtime +"$STALE_DAYS" -exec rm -rf {} + 2>/dev/null

after_n="$(count)"
echo "$(stamp) $ME  before: ${before_n} procs / ${before_mb:-0} MB   after: ${after_n} procs" >> "$LOG"
# keep the log short
tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"