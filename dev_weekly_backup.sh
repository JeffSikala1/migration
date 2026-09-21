#!/usr/bin/env bash
set -euo pipefail

# Weekly rollup — copies each day's nightly output from the past 7 days
# into a weekly/ prefix for longer retention.
#
# BUG FIX (2026-09-21): the original version used DATE="$(date +%G-W%V)"
# (ISO week, e.g. "2026-W38") as the SOURCE prefix to sync from, but
# dev_nightly_backup.sh writes to daily date prefixes like "2026-09-20"
# ($(date +%F)). Those two never matched, so `aws s3 sync` was syncing
# from a prefix that never had anything in it — silently copying zero
# files every week since this was first deployed. (This pattern was
# copied from prod's weekly_backup.sh, which appears to have the same
# mismatch — worth checking prod's weekly/ prefix independently.)
#
# Fix: sync each of the last 7 daily date prefixes into a single
# ISO-week-named weekly/ destination folder, so the destination still
# groups by week (matching the original intent) while the source
# prefixes actually match what nightly writes.

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