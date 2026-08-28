#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
BUCKET="s3://cnxs-atlassian-backups"
DATE="$(date +%F)"
TS="$(date +%Y%m%d_%H%M%S)"
BIN_BASE="/app/bamboobackup/atlassian-backups"     # script + logs stay here (small)
STAGE_ROOT="${STAGE_ROOT:-/backup-staging}"        # actual tar/dump staging - NOT on /app
STAGE="${STAGE_ROOT}/${DATE}/${TS}"
LOGDIR="${BIN_BASE}/logs"
LOG="${LOGDIR}/nightly-${DATE}.log"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
AWS_REGION="${AWS_REGION:-us-east-1}"

PG_CONTAINER="${PG_CONTAINER:-prod-postgres}"
DB_LIST=(${DB_LIST:-bitbucket bamboo})   # space-separated, override if needed

# Named volumes this script backs up, and which subdir minimally proves the
# tar actually captured live content (used by the post-backup sanity check).
declare -A VOLUME_SANITY_PATH=(
  ["bitbucketVolume"]="shared/keys"
  ["optbitbucketVolume"]=""
  ["bambooVolume"]="shared/configuration"
  ["optbambooVolume"]=""
  ["nginxVolume"]=""
)

mkdir -p "$STAGE" "$LOGDIR"
exec > >(tee -a "$LOG") 2>&1

echo "==== Nightly backup start: ${TS} host=${HOSTNAME} ===="
echo "Staging to: ${STAGE} (filesystem: $(df -h --output=target "$STAGE_ROOT" | tail -1))"

# ===== Helpers =====
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1"; exit 2; }; }
need aws
need docker
need tar

have_jq=0
if command -v jq >/dev/null 2>&1; then
  have_jq=1
else
  echo "WARN: jq not found; metadata.json will be minimal."
fi

s3_put_dir() {
  local src="$1" dest="$2"
  aws s3 cp "$src" "$dest" --recursive
}

s3_put_file() {
  local src="$1" dest="$2"
  aws s3 cp "$src" "$dest"
}

# Resolve a named Docker volume
resolve_volume_path() {
  local vol="$1"
  local path
  if ! path="$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null)"; then
    echo "ERROR: docker volume '$vol' not found — cannot resolve mountpoint. Aborting."
    exit 4
  fi
  if [[ -z "$path" || ! -d "$path" ]]; then
    echo "ERROR: resolved mountpoint for volume '$vol' is empty or does not exist: '$path'. Aborting."
    exit 4
  fi
  echo "$path"
}

# Post-backup sanity check
sanity_check_tar() {
  local tarfile="$1" vol="$2" expect_subpath="$3"
  local size_bytes
  size_bytes="$(stat -c '%s' "$tarfile" 2>/dev/null || echo 0)"
  echo "  - sanity: ${tarfile} = ${size_bytes} bytes"

  if [[ "$size_bytes" -lt 10240 ]]; then
    echo "  WARN: ${tarfile} is suspiciously small (<10KB) for volume '${vol}' — likely capturing an empty or stale path."
  fi

  if [[ -n "$expect_subpath" ]]; then
    local match_count
    match_count="$(tar -tzf "$tarfile" 2>/dev/null | grep -c "${expect_subpath}" || true)"
    if [[ "${match_count:-0}" -eq 0 ]]; then
      echo "  WARN: ${tarfile} does NOT contain expected path '*${expect_subpath}*' for volume '${vol}'. This backup may be incomplete — investigate before relying on it for restore."
    else
      echo "  OK: ${tarfile} contains expected path '*${expect_subpath}*' (${match_count} matches)"
    fi
  fi
}

# Preflight
preflight_check_space() {
  local vol_paths=("$@")
  local needed_kb=0 avail_kb path size_kb

  for path in "${vol_paths[@]}"; do
    size_kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    needed_kb=$(( needed_kb + ${size_kb:-0} ))
  done

  # Headroom multiplier: tars are compressed (~smaller) but we're staging
  # bitbucket + bamboo + postgres dumps + nginx concurrently, so budget
  # generously rather than cut it close.
  local needed_with_margin_kb=$(( needed_kb * 3 / 2 ))
  avail_kb="$(df -k --output=avail "$STAGE_ROOT" | tail -1 | tr -d ' ')"

  echo "  - preflight: source volumes ~$(( needed_kb / 1024 / 1024 ))G, need ~$(( needed_with_margin_kb / 1024 / 1024 ))G free on $(df -h --output=target "$STAGE_ROOT" | tail -1), have $(( avail_kb / 1024 / 1024 ))G"

  if [[ "$avail_kb" -lt "$needed_with_margin_kb" ]]; then
    echo "ERROR: insufficient free space on staging filesystem (${STAGE_ROOT}). Need ~$(( needed_with_margin_kb / 1024 / 1024 ))G, have $(( avail_kb / 1024 / 1024 ))G. Aborting before writing any tar."
    echo "        Clean up stale staging dirs under ${STAGE_ROOT}, or free space on that filesystem, then re-run."
    exit 5
  fi
}

# Tar a live application volume tolerantly
tar_tolerant() {
  local rc=0
  tar "$@" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    return 0
  elif [[ "$rc" -eq 1 ]]; then
    echo "  WARN: tar exited 1 (benign - e.g. a live app file changed mid-read). Archive is usable, continuing."
    return 0
  else
    echo "ERROR: tar exited ${rc} (fatal) for: $*"
    return "$rc"
  fi
}

# ===== 1) Postgres dumps (logical) =====
echo "[1/5] Postgres dumps..."
mkdir -p "$STAGE/postgres"

if ! docker ps --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  echo "ERROR: Postgres container '$PG_CONTAINER' not running. Aborting."
  exit 3
fi

echo "  - dumping globals (roles/grants)"
docker exec "$PG_CONTAINER" pg_dumpall -U postgres --globals-only \
  > "$STAGE/postgres/globals_${TS}.sql"

for DB in "${DB_LIST[@]}"; do
  echo "  - dumping ${DB}"
  docker exec "$PG_CONTAINER" pg_dump -U postgres -Fc "$DB" \
    > "$STAGE/postgres/${DB}_${TS}.dump"
done

# ===== 2) Atlassian volumes (tar) =====
echo "[2/5] Atlassian volume backups..."
mkdir -p "$STAGE/apps"

BITBUCKET_VOL_PATH="$(resolve_volume_path bitbucketVolume)"
OPTBITBUCKET_VOL_PATH="$(resolve_volume_path optbitbucketVolume)"
BAMBOO_VOL_PATH="$(resolve_volume_path bambooVolume)"
OPTBAMBOO_VOL_PATH="$(resolve_volume_path optbambooVolume)"

echo "  - bitbucketVolume    -> ${BITBUCKET_VOL_PATH}"
echo "  - optbitbucketVolume -> ${OPTBITBUCKET_VOL_PATH}"
echo "  - bambooVolume       -> ${BAMBOO_VOL_PATH}"
echo "  - optbambooVolume    -> ${OPTBAMBOO_VOL_PATH}"

preflight_check_space "$BITBUCKET_VOL_PATH" "$OPTBITBUCKET_VOL_PATH" "$BAMBOO_VOL_PATH" "$OPTBAMBOO_VOL_PATH"

tar_tolerant -czf "$STAGE/apps/bitbucket_${TS}.tar.gz" -C / \
  "${BITBUCKET_VOL_PATH#/}" "${OPTBITBUCKET_VOL_PATH#/}"

tar_tolerant -czf "$STAGE/apps/bamboo_${TS}.tar.gz" -C / \
  "${BAMBOO_VOL_PATH#/}" "${OPTBAMBOO_VOL_PATH#/}"

sanity_check_tar "$STAGE/apps/bitbucket_${TS}.tar.gz" "bitbucketVolume" "${VOLUME_SANITY_PATH[bitbucketVolume]}"
sanity_check_tar "$STAGE/apps/bamboo_${TS}.tar.gz"    "bambooVolume"    "${VOLUME_SANITY_PATH[bambooVolume]}"

# ===== 3) NGINX + TLS/certs/config =====
echo "[3/5] NGINX + TLS backup..."
mkdir -p "$STAGE/nginx"

NGINX_VOL_PATH="$(resolve_volume_path nginxVolume)"
echo "  - nginxVolume -> ${NGINX_VOL_PATH}"

tar -czf "$STAGE/nginx/nginx_tls_${TS}.tar.gz" \
  /etc/nginx \
  "$NGINX_VOL_PATH" \
  /etc/ssl \
  /etc/pki \
  2>/dev/null || true

# ===== 4) Metadata =====
echo "[4/5] Metadata..."
if [[ "$have_jq" -eq 1 ]]; then
  cat > "$STAGE/metadata.json" <<JSON
{
  "timestamp": "${TS}",
  "date": "${DATE}",
  "host": "${HOSTNAME}",
  "region": "${AWS_REGION}",
  "containers": $(docker ps --format '{{json .}}' | jq -s '.'),
  "docker_volumes": $(docker volume ls --format '{{.Name}}' | jq -R -s -c 'split("\n")[:-1]'),
  "docker_root_dir": "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo unknown)",
  "resolved_volume_paths": {
    "bitbucketVolume": "${BITBUCKET_VOL_PATH}",
    "optbitbucketVolume": "${OPTBITBUCKET_VOL_PATH}",
    "bambooVolume": "${BAMBOO_VOL_PATH}",
    "optbambooVolume": "${OPTBAMBOO_VOL_PATH}",
    "nginxVolume": "${NGINX_VOL_PATH}"
  }
}
JSON
else
  cat > "$STAGE/metadata.json" <<JSON
{
  "timestamp": "${TS}",
  "date": "${DATE}",
  "host": "${HOSTNAME}",
  "region": "${AWS_REGION}",
  "note": "jq not installed; container/volume inventory omitted",
  "docker_root_dir": "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo unknown)"
}
JSON
fi

# ===== 5) Upload to S3 =====
echo "[5/5] Uploading to S3..."
s3_put_dir  "$STAGE/postgres" "${BUCKET}/postgres/${DATE}/"
s3_put_dir  "$STAGE/apps"     "${BUCKET}/apps/${DATE}/"
s3_put_dir  "$STAGE/nginx"    "${BUCKET}/nginx/${DATE}/"
s3_put_file "$STAGE/metadata.json" "${BUCKET}/metadata/${DATE}/metadata_${TS}.json"

# ===== EBS snapshots (same run) =====
echo "[EXTRA] EBS snapshots..."
TOKEN_IMDS="$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"

INSTANCE_ID="$(curl -sH "X-aws-ec2-metadata-token: $TOKEN_IMDS" \
  http://169.254.169.254/latest/meta-data/instance-id)"

AZ="$(curl -sH "X-aws-ec2-metadata-token: $TOKEN_IMDS" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)"

REGION="${AZ::-1}"

VOL_IDS="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId" --output text)"

declare -A VOL_PURPOSE
VOL_PURPOSE["vol-08f7bca75e08f0d3f"]="root"
VOL_PURPOSE["vol-05ebadfa92a493533"]="app"
VOL_PURPOSE["vol-04e3115aea57b5c70"]="backup"

for VOL in $VOL_IDS; do
  echo "  - snapshotting volume $VOL"
  PURPOSE_TAG="${VOL_PURPOSE[$VOL]:-unknown}"
  SNAP_ID="$(aws ec2 create-snapshot --region "$REGION" --volume-id "$VOL" \
    --description "Nightly Atlassian backup ${HOSTNAME} ${TS}" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=cnxs-atlassian-nightly},{Key=Host,Value=${HOSTNAME}},{Key=Date,Value=${DATE}},{Key=Timestamp,Value=${TS}},{Key=Purpose,Value=atlassian-backup},{Key=VolumePurpose,Value=${PURPOSE_TAG}}]" \
    --query SnapshotId --output text)"
  echo "    created snapshot: $SNAP_ID"
done

echo "==== Nightly backup completed OK ===="

echo "Cleaning up local staging..."
rm -rf "$STAGE"