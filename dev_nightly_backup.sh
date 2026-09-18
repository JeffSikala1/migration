#!/usr/bin/env bash
set -euo pipefail

# Dev/OSS nightly backup — Bitbucket, Bamboo, Artifactory, Postgres
# No s3 backend here, so full backups are staged locally first
# Exception: the Artifactory filestore is too big to stage, streamed straight to S3

# ===== Config =====
BUCKET="s3://cnxs-dev-atlassian-backups"
DATE="$(date +%F)"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="/app/devbackup"
STAGE_ROOT="${STAGE_ROOT:-/backup-staging}"
STAGE="${STAGE_ROOT}/${DATE}/${TS}"
LOGDIR="${BASE}/logs"
LOG="${LOGDIR}/nightly-${DATE}.log"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
AWS_REGION="${AWS_REGION:-us-east-1}"

# One dev-postgres backs all three apps; superuser is artifactory, not postgres
PG_CONTAINER="${PG_CONTAINER:-dev-postgres}"
PG_USER="${PG_USER:-artifactory}"
DB_LIST=(${DB_LIST:-bitbucket bamboo artifactory})

BITBUCKET_CONTAINER="${BITBUCKET_CONTAINER:-dev-bitbucket}"
BAMBOO_CONTAINER="${BAMBOO_CONTAINER:-dev-bamboo}"
ARTIFACTORY_CONTAINER="${ARTIFACTORY_CONTAINER:-dev-artifactory}"

# Bitbucket config paths; excludes shared/data.
BITBUCKET_CONFIG_PATHS=(
  "shared/bitbucket.properties"
  "shared/secrets-config.yaml"
  "shared/keys"
  "shared/config"
)
BAMBOO_CONFIG_PATHS=(
  "shared/configuration"         # bamboo-shared.cfg.xml, broker.ks, bamboo-mail.cfg.xml,
                                  # cipher/, keys/ (AES keys), secrets-config.yaml,
                                  # administration.xml, secured/ (52K)
  "shared/ssl"                   # ca.key, ca.crt (8K)
  "shared/clusterInfo"           # info.xml (4K)
)
# bamboo.cfg.xml lives at the container's application-data ROOT, not under
# shared/ — captured separately below, not via BAMBOO_CONFIG_PATHS.
BAMBOO_ROOT_CONFIG_FILES=(
  "bamboo.cfg.xml"
)

# Artifactory keys only; filestore is handled separately.
ARTIFACTORY_CONFIG_PATHS=(
  "etc/artifactory/security"
  "etc/security/keys"
  "etc/access/keys"
  "etc/jfconnect/keys"
  "etc/event/keys"
)
ARTIFACTORY_FILESTORE_PATH="data/artifactory/filestore"

mkdir -p "$STAGE" "$LOGDIR"
exec > >(tee -a "$LOG") 2>&1

echo "==== Dev nightly backup start: ${TS} host=${HOSTNAME} ===="
echo "Staging to: ${STAGE}"

# ===== Helpers =====
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1"; exit 2; }; }
need aws
need docker
need tar

have_jq=0
command -v jq >/dev/null 2>&1 && have_jq=1 || echo "WARN: jq not found; metadata.json will be minimal."

have_pv=0
command -v pv >/dev/null 2>&1 && have_pv=1 || echo "WARN: pv not found; filestore stream will have no progress meter."

s3_put_dir()  { aws s3 cp "$1" "$2" --recursive; }
s3_put_file() { aws s3 cp "$1" "$2"; }

# Resolve a running container's data volume mountpoint on the host.
# Usage: resolve_container_mount <container_name> <mount_dest_in_container>
resolve_container_mount() {
  local container="$1" dest="$2" path
  path="$(docker inspect "$container" \
    --format "{{range .Mounts}}{{if eq .Destination \"${dest}\"}}{{.Source}}{{end}}{{end}}" 2>/dev/null)"
  if [[ -z "$path" || ! -d "$path" ]]; then
    echo "ERROR: could not resolve mount '${dest}' for container '${container}'. Aborting."
    exit 4
  fi
  echo "$path"
}

tar_config_subset() {
  local out="$1" base="$2"; shift 2
  local paths=("$@") existing=()
  local p
  for p in "${paths[@]}"; do
    [[ -e "${base}/${p}" ]] && existing+=("$p")
  done
  if [[ "${#existing[@]}" -eq 0 ]]; then
    echo "  WARN: none of the expected config paths exist under ${base} — skipping ${out}"
    return
  fi
  tar -czf "$out" -C "$base" "${existing[@]}"
  echo "  - wrote ${out} ($(stat -c '%s' "$out" 2>/dev/null || echo '?') bytes) containing: ${existing[*]}"
}

# ===== 1) Postgres dumps (full — this is our only copy) =====
echo "[1/4] Postgres dumps (bitbucket, bamboo, artifactory)..."
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

# ===== 2) Bitbucket / Bamboo config-only backup =====
echo "[2/4] Bitbucket / Bamboo config-only backup..."
mkdir -p "$STAGE/apps"

if docker ps --format '{{.Names}}' | grep -qx "$BITBUCKET_CONTAINER"; then
  BITBUCKET_HOME="$(resolve_container_mount "$BITBUCKET_CONTAINER" "/var/atlassian/application-data/bitbucket")"
  echo "  - ${BITBUCKET_CONTAINER} home -> ${BITBUCKET_HOME}"
  tar_config_subset "$STAGE/apps/bitbucket_config_${TS}.tar.gz" "$BITBUCKET_HOME" "${BITBUCKET_CONFIG_PATHS[@]}"
else
  echo "  WARN: ${BITBUCKET_CONTAINER} not running — skipping Bitbucket config backup."
fi

if docker ps --format '{{.Names}}' | grep -qx "$BAMBOO_CONTAINER"; then
  BAMBOO_HOME="$(resolve_container_mount "$BAMBOO_CONTAINER" "/var/atlassian/application-data/bamboo")"
  echo "  - ${BAMBOO_CONTAINER} home -> ${BAMBOO_HOME}"
  tar_config_subset "$STAGE/apps/bamboo_config_${TS}.tar.gz" "$BAMBOO_HOME" \
    "${BAMBOO_CONFIG_PATHS[@]}" "${BAMBOO_ROOT_CONFIG_FILES[@]}"
else
  echo "  WARN: ${BAMBOO_CONTAINER} not running — skipping Bamboo config backup."
fi

# ===== 3) Artifactory: config (staged) + filestore (streamed) =====
echo "[3/4] Artifactory config + filestore backup..."

if docker ps --format '{{.Names}}' | grep -qx "$ARTIFACTORY_CONTAINER"; then
  ARTIFACTORY_HOME="$(resolve_container_mount "$ARTIFACTORY_CONTAINER" "/var/opt/jfrog/artifactory")"
  echo "  - ${ARTIFACTORY_CONTAINER} home -> ${ARTIFACTORY_HOME}"
  tar_config_subset "$STAGE/apps/artifactory_config_${TS}.tar.gz" "$ARTIFACTORY_HOME" "${ARTIFACTORY_CONFIG_PATHS[@]}"

  FILESTORE_DIR="${ARTIFACTORY_HOME}/${ARTIFACTORY_FILESTORE_PATH}"
  if [[ -d "$FILESTORE_DIR" ]]; then
    FILESTORE_DEST="${BUCKET}/apps/${DATE}/artifactory_filestore_${TS}.tar.gz"
    # --expected-size is required for streams over 50GB
    FILESTORE_SIZE="$(du -sb "$FILESTORE_DIR" | cut -f1)"
    echo "  - streaming filestore (${FILESTORE_DIR}) to ${FILESTORE_DEST}"
    if [[ "$have_pv" -eq 1 ]]; then
      tar -czf - -C "$(dirname "$FILESTORE_DIR")" "$(basename "$FILESTORE_DIR")" \
        | pv -pterab \
        | aws s3 cp - "$FILESTORE_DEST" --expected-size "$FILESTORE_SIZE"
    else
      tar -czf - -C "$(dirname "$FILESTORE_DIR")" "$(basename "$FILESTORE_DIR")" \
        | aws s3 cp - "$FILESTORE_DEST" --expected-size "$FILESTORE_SIZE"
    fi
    echo "  - filestore stream complete"
  else
    echo "  WARN: filestore dir not found at ${FILESTORE_DIR} — skipping filestore stream."
  fi
else
  echo "  WARN: ${ARTIFACTORY_CONTAINER} not running — skipping Artifactory backup."
fi

# ===== 4) Metadata + upload =====
echo "[4/4] Metadata + upload..."
if [[ "$have_jq" -eq 1 ]]; then
  cat > "$STAGE/metadata.json" <<JSON
{
  "timestamp": "${TS}",
  "date": "${DATE}",
  "host": "${HOSTNAME}",
  "region": "${AWS_REGION}",
  "scope": "config-only (bitbucket/bamboo), config + full filestore (artifactory), full postgres dumps",
  "containers": $(docker ps --format '{{json .}}' | jq -s '.')
}
JSON
else
  cat > "$STAGE/metadata.json" <<JSON
{ "timestamp": "${TS}", "date": "${DATE}", "host": "${HOSTNAME}", "region": "${AWS_REGION}", "note": "jq not installed" }
JSON
fi

s3_put_dir  "$STAGE/postgres" "${BUCKET}/postgres/${DATE}/"
s3_put_dir  "$STAGE/apps"     "${BUCKET}/apps/${DATE}/"
s3_put_file "$STAGE/metadata.json" "${BUCKET}/metadata/${DATE}/metadata_${TS}.json"

echo "==== Dev nightly backup completed OK ===="

echo "Cleaning up local staging..."
rm -rf "$STAGE"
