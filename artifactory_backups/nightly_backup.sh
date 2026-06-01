#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
BUCKET="s3://cnxs-artifactory-backups"
DATE="$(date +%F)"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="/app/artifactorybackup"
STAGE="${BASE}/staging/${DATE}/${TS}"
LOGDIR="${BASE}/logs"
LOG="${LOGDIR}/nightly-${DATE}.log"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
AWS_REGION="${AWS_REGION:-us-east-1}"

PG_CONTAINER="${PG_CONTAINER:-artifactory-postgres}"
PG_USER="artifactory"
DB_LIST=(${DB_LIST:-artifactory})

mkdir -p "$STAGE" "$LOGDIR"
exec > >(tee -a "$LOG") 2>&1

echo "==== Artifactory nightly backup start: ${TS} host=${HOSTNAME} ===="

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
echo "[1/5] Postgres dumps..."
mkdir -p "$STAGE/postgres"

if ! docker ps --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  echo "ERROR: Postgres container '$PG_CONTAINER' not running. Aborting."
  exit 3
fi

echo "  - dumping globals (roles/grants)"
docker exec "$PG_CONTAINER" pg_dumpall -U "$PG_USER" --globals-only \
  > "$STAGE/postgres/globals_${TS}.sql"

for DB in "${DB_LIST[@]}"; do
  echo "  - dumping ${DB}"
  docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" -Fc "$DB" \
    > "$STAGE/postgres/${DB}_${TS}.dump"
done

# ===== 2) Artifactory volumes (tar) =====
# NOTE: Filestore is excluded — it is already backed by the
# conexus-artifactory-filestore S3 bucket natively via Artifactory.
# Nginx TLS certs are excluded — managed and backed up by the
# Atlassian backup on .34 (shared wildcard cert).
echo "[2/5] Artifactory volume backups..."
mkdir -p "$STAGE/apps"

tar -czf "$STAGE/apps/artifactory_var_${TS}.tar.gz" \
  /app/jfrog/artifactory/var

tar -czf "$STAGE/apps/artifactory_security_${TS}.tar.gz" \
  /app/jfrog/artifactory/security

# ===== 3) Artifactory crypto / keystores =====
echo "[3/5] Artifactory crypto safety backup..."
mkdir -p "$STAGE/crypto"

# master.key and join.key live under var/etc/security — already captured
# in the var tarball above, but snapshot them explicitly as a safety net.
tar -czf "$STAGE/crypto/artifactory_keys_${TS}.tar.gz" \
  /app/jfrog/artifactory/var/etc/security \
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

# ===== 5) Upload to S3 =====
echo "[5/5] Uploading to S3..."
s3_put_dir  "$STAGE/postgres" "${BUCKET}/postgres/${DATE}/"
s3_put_dir  "$STAGE/apps"     "${BUCKET}/apps/${DATE}/"
s3_put_dir  "$STAGE/crypto"   "${BUCKET}/crypto/${DATE}/"
s3_put_file "$STAGE/metadata.json" "${BUCKET}/metadata/${DATE}/metadata_${TS}.json"

# ===== EBS snapshots =====
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
VOL_PURPOSE["vol-078ee09ac10c02f62"]="root"
VOL_PURPOSE["vol-060bb45ae6b8d71bc"]="artifactory"
VOL_PURPOSE["vol-04f0ab9e32f79dc75"]="postgres"

for VOL in $VOL_IDS; do
  echo "  - snapshotting volume $VOL"
  PURPOSE_TAG="${VOL_PURPOSE[$VOL]:-unknown}"
  SNAP_ID="$(aws ec2 create-snapshot --region "$REGION" --volume-id "$VOL" \
    --description "Nightly Artifactory backup ${HOSTNAME} ${TS}" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=cnxs-artifactory-nightly},{Key=Host,Value=${HOSTNAME}},{Key=Date,Value=${DATE}},{Key=Timestamp,Value=${TS}},{Key=Purpose,Value=artifactory-backup},{Key=VolumePurpose,Value=${PURPOSE_TAG}}]" \
    --query SnapshotId --output text)"
  echo "    created snapshot: $SNAP_ID"
done

echo "==== Artifactory nightly backup completed OK ===="

# Cleanup local staging after successful upload
echo "Cleaning up local staging..."
rm -rf "$STAGE"