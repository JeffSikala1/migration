#!/usr/bin/env bash
set -euo pipefail

BUCKET="s3://cnxs-atlassian-backups"

DAY="$(date +%F)"          # 2026-01-06
WEEK="$(date +%G-W%V)"     # 2026-W02

aws s3 sync "${BUCKET}/postgres/${DAY}/"  "${BUCKET}/weekly/${WEEK}/postgres/${DAY}/"
aws s3 sync "${BUCKET}/apps/${DAY}/"      "${BUCKET}/weekly/${WEEK}/apps/${DAY}/"
aws s3 sync "${BUCKET}/nginx/${DAY}/"     "${BUCKET}/weekly/${WEEK}/nginx/${DAY}/"
aws s3 sync "${BUCKET}/crypto/${DAY}/"    "${BUCKET}/weekly/${WEEK}/crypto/${DAY}/"
aws s3 sync "${BUCKET}/metadata/${DAY}/"  "${BUCKET}/weekly/${WEEK}/metadata/${DAY}/"