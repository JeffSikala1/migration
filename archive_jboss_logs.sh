#!/usr/bin/env bash
set -euo pipefail

LOGDIR="/app/jboss-eap-8.0/standalone/log"
NAS_BASE="/NSFS_NAS/database/jboss-log-archive"
STAMP=$(date -d "last month" +%Y-%m)   # e.g. 2025-06

# 1) Compress plain logs older than the 1st of this month
find "$LOGDIR" -maxdepth 1 -type f -name '*.log' \
     ! -newermt "$(date +%Y-%m-01)" \
     -print -exec gzip {} \;

# 2) Create month folder on NAS and move the freshly-compressed logs
mkdir -p "$NAS_BASE/$STAMP"
mv "$LOGDIR"/*"$STAMP"*.gz "$NAS_BASE/$STAMP"/ 2>/dev/null || true

# 3) Prune NAS archives older than 6 months
find "$NAS_BASE" -type f -name '*.gz' -mtime +180 -delete

# 4) Show result
echo "After archive →"
df -h /app | grep /app

# -type f  : regular files
# -name '*.log*' catches .log, .log.1, .log.20250617 etc.
find "$LOGDIR" -maxdepth 1 -type f ! -name '*.gz' -name '*.log*' -print -exec gzip {} \;

# Loop over each .gz file that remains in LOGDIR
for gz in "$LOGDIR"/*.gz; do
    # Skip loop if no files (bash will echo pattern)
    [ -e "$gz" ] || break
    
    # Extract YYYY-MM from filename’s mtime (not name) to bucket correctly
    stamp=$(date -r "$gz" +%Y-%m)
    dest="$NAS/$stamp"
    
    mkdir -p "$dest"
    mv "$gz" "$dest"/
done