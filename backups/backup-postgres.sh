#!/usr/bin/env bash
set -euo pipefail

DATE=$(date +%F)
BACKUP_DIR="/tmp/postgres-backup-${DATE}"
S3_BUCKET="s3://cnxs-atlassian-backups/postgres/${DATE}"

mkdir -p "$BACKUP_DIR"

echo "Backing up Bitbucket DB..."
docker exec prod-postgres \
  pg_dump -U postgres -Fc bitbucket \
  > "${BACKUP_DIR}/bitbucket.dump"

echo "Backing up Bamboo DB..."
docker exec prod-postgres \
  pg_dump -U postgres -Fc bamboo \
  > "${BACKUP_DIR}/bamboo.dump"

aws s3 cp "${BACKUP_DIR}" "${S3_BUCKET}" --recursive

rm -rf "$BACKUP_DIR"