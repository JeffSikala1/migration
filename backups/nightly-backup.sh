#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
BUCKET="s3://cnxs-atlassian-backups"
DATE="$(date +%F)"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="/app/bamboobackup/atlassian-backups"
STAGE="${BASE}/staging/${DATE}/${TS}"
LOGDIR="${BASE}/logs"
LOG="${LOGDIR}/nightly-${DATE}.log"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
AWS_REGION="${AWS_REGION:-us-east-1}"

PG_CONTAINER="${PG_CONTAINER:-prod-postgres}"
DB_LIST=(${DB_LIST:-bitbucket bamboo})   # space-separated, override if needed

mkdir -p "$STAGE" "$LOGDIR"
exec > >(tee -a "$LOG") 2>&1

echo "==== Nightly backup start: ${TS} host=${HOSTNAME} ===="

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

# ===== 1) Postgres dumps (logical) =====
echo "[1/6] Postgres dumps..."
mkdir -p "$STAGE/postgres"

# quick sanity check container exists
if ! docker ps --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  echo "ERROR: Postgres container '$PG_CONTAINER' not running. Aborting."
  exit 3
fi

# Dump globals (roles, grants) - optional but recommended
echo "  - dumping globals (roles/grants)"
docker exec "$PG_CONTAINER" pg_dumpall -U postgres --globals-only \
  > "$STAGE/postgres/globals_${TS}.sql"

for DB in "${DB_LIST[@]}"; do
  echo "  - dumping ${DB}"
  docker exec "$PG_CONTAINER" pg_dump -U postgres -Fc "$DB" \
    > "$STAGE/postgres/${DB}_${TS}.dump"
done

# ===== 2) Atlassian volumes (tar) =====
echo "[2/6] Atlassian volume backups..."
mkdir -p "$STAGE/apps"

tar -czf "$STAGE/apps/bitbucket_${TS}.tar.gz" \
  /var/lib/docker/volumes/bitbucketVolume/_data \
  /var/lib/docker/volumes/optbitbucketVolume/_data

tar -czf "$STAGE/apps/bamboo_${TS}.tar.gz" \
  /var/lib/docker/volumes/bambooVolume/_data \
  /var/lib/docker/volumes/optbambooVolume/_data

# ===== 3) NGINX + TLS/certs/config =====
echo "[3/6] NGINX + TLS backup..."
mkdir -p "$STAGE/nginx"

# Include common cert locations; ignore missing
tar -czf "$STAGE/nginx/nginx_tls_${TS}.tar.gz" \
  /etc/nginx \
  /var/lib/docker/volumes/nginxVolume/_data \
  /etc/ssl \
  /etc/pki \
  2>/dev/null || true

# ===== 4) Bamboo keystores (explicit safety net) =====
echo "[4/6] Bamboo keystore safety backup..."
mkdir -p "$STAGE/crypto"

tar -czf "$STAGE/crypto/bamboo_keystores_${TS}.tar.gz" \
  /var/lib/docker/volumes/bambooVolume/_data \
  /var/lib/docker/volumes/optbambooVolume/_data \
  2>/dev/null || true

# ===== 5) Metadata =====
echo "[5/6] Metadata..."
if [[ "$have_jq" -eq 1 ]]; then
  cat > "$STAGE/metadata.json" <<JSON
{
  "timestamp": "${TS}",
  "date": "${DATE}",
  "host": "${HOSTNAME}",
  "region": "${AWS_REGION}",
  "containers": $(docker ps --format '{{json .}}' | jq -s '.'),
  "docker_volumes": $(docker volume ls --format '{{.Name}}' | jq -R -s -c 'split("\n")[:-1]')
}
JSON
else
  cat > "$STAGE/metadata.json" <<JSON
{
  "timestamp": "${TS}",
  "date": "${DATE}",
  "host": "${HOSTNAME}",
  "region": "${AWS_REGION}",
  "note": "jq not installed; container/volume inventory omitted"
}
JSON
fi

# ===== 6) Upload to S3 =====
echo "[6/6] Uploading to S3..."
s3_put_dir  "$STAGE/postgres" "${BUCKET}/postgres/${DATE}/"
s3_put_dir  "$STAGE/apps"     "${BUCKET}/apps/${DATE}/"
s3_put_dir  "$STAGE/nginx"    "${BUCKET}/nginx/${DATE}/"
s3_put_dir  "$STAGE/crypto"   "${BUCKET}/crypto/${DATE}/"
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

# Find attached EBS volume IDs
VOL_IDS="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId" --output text)"

# Map volume IDs to mount purpose using NVMe serial mapping (common on Nitro)
# This is best-effort; if it can't map, we still snapshot.
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

# Cleanup local staging after successful upload
echo "Cleaning up local staging..."
rm -rf "$STAGE"