#!/usr/bin/env bash
set -euo pipefail

BUCKET="s3://cnxs-atlassian-backups"
DATE="$(date +%G-W%V)"

aws s3 sync "${BUCKET}/postgres/${DATE}/" "${BUCKET}/weekly/postgres/${DATE}/"
aws s3 sync "${BUCKET}/apps/${DATE}/"     "${BUCKET}/weekly/apps/${DATE}/"
aws s3 sync "${BUCKET}/nginx/${DATE}/"    "${BUCKET}/weekly/nginx/${DATE}/"
aws s3 sync "${BUCKET}/metadata/${DATE}/" "${BUCKET}/weekly/metadata/${DATE}/"