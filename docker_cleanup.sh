#!/bin/bash

set -u

LOG=/var/log/docker-cleanup.log
echo "===== $(date '+%Y-%m-%d %H:%M:%S') Starting docker cleanup =====" >> "$LOG"

# Remove unused images (not referenced by any container) older than 1 hour
docker image prune -a -f --filter "until=1h" 2>&1 | tee -a "$LOG"

# Remove stopped containers older than 1 hour
docker container prune -f --filter "until=1h" 2>&1 | tee -a "$LOG"

echo "===== Finished docker cleanup =====" >> "$LOG"