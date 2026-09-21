#!/usr/bin/env bash
set -euo pipefail

BUCKET="s3://cnxs-dev-atlassian-backups"
WEEK_LABEL="$(date +%G-W%V)"

for i in 0 1 2 3 4 5 6; do
  D="$(date -d "-${i} day" +%F)"
  for PREFIX in postgres apps metadata; do
    SRC="${BUCKET}/${PREFIX}/${D}/"
    DEST="${BUCKET}/weekly/${PREFIX}/${WEEK_LABEL}/${D}/"
    echo "Syncing ${SRC} -> ${DEST}"
    aws s3 sync "$SRC" "$DEST"
  done
done