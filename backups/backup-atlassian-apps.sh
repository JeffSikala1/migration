#!/usr/bin/env bash
set -euo pipefail

DATE=$(date +%F)
TMP="/tmp/atlassian-${DATE}"
S3="s3://cnxs-atlassian-backups"

mkdir -p "$TMP"

echo "Backing up Bitbucket..."
tar -czf "$TMP/bitbucket.tar.gz" \
  /var/lib/docker/volumes/bitbucketVolume/_data \
  /var/lib/docker/volumes/optbitbucketVolume/_data

echo "Backing up Bamboo..."
tar -czf "$TMP/bamboo.tar.gz" \
  /var/lib/docker/volumes/bambooVolume/_data \
  /var/lib/docker/volumes/optbambooVolume/_data

aws s3 cp "$TMP/bitbucket.tar.gz" "$S3/bitbucket/${DATE}/"
aws s3 cp "$TMP/bamboo.tar.gz" "$S3/bamboo/${DATE}/"

rm -rf "$TMP"