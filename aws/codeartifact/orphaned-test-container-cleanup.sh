#!/bin/bash

set -u
LOG=/var/log/orphaned-test-container-cleanup.log
ORPHAN_AGE_SECONDS=21600   # 6 hours

echo "===== $(date '+%Y-%m-%d %H:%M:%S') Starting orphan check =====" >> "$LOG"

# Match only containers whose names START WITH jboss-cnx-it- or postgres-cnx-it-
ORPHAN_IDS=$(docker ps \
  --filter "name=^jboss-cnx-it-" \
  --filter "name=^postgres-cnx-it-" \
  --format "{{.ID}}")

if [ -z "$ORPHAN_IDS" ]; then
  echo "$(date '+%H:%M:%S') No matching test containers running" >> "$LOG"
  exit 0
fi

echo "$ORPHAN_IDS" | while read CID; do
  if [ -z "$CID" ]; then continue; fi

  STARTED_AT=$(docker inspect -f '{{.State.StartedAt}}' "$CID" 2>/dev/null)
  if [ -z "$STARTED_AT" ]; then continue; fi

  STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null)
  if [ -z "$STARTED_EPOCH" ]; then continue; fi
  
  NOW_EPOCH=$(date +%s)
  AGE=$((NOW_EPOCH - STARTED_EPOCH))

  CNAME=$(docker inspect -f '{{.Name}}' "$CID" | sed 's|^/||')

  if [ "$AGE" -gt "$ORPHAN_AGE_SECONDS" ]; then
    echo "$(date '+%H:%M:%S') Stopping orphan: $CNAME (age: $((AGE/3600))h)" >> "$LOG"
    docker stop "$CID" >> "$LOG" 2>&1
    docker rm "$CID" >> "$LOG" 2>&1
  fi
done

echo "===== Finished orphan check =====" >> "$LOG"