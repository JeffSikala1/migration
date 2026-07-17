#!/usr/bin/env bash

set -u
LOG_TAG="start-bamboo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "${SCRIPT_DIR}/lib-common.sh"

log "=== start-bamboo.sh beginning ==="

# require the expected mountpoint and Docker volumes/networks to exist before starting anything. This is a sanity check to avoid starting against an empty root disk directory or missing volumes/networks.
require_path "/app" "docker data mount"
mountpoint -q /app || fail "/app is not a mountpoint - refusing to start (would risk running against an empty root-disk directory)"
require_volume "pgdataVolume16"
require_volume "bambooVolume"
require_network "prod-net"

# Postgres
ensure_started "prod-postgres"
wait_for_postgres "prod-postgres" "postgres" 90

# Bamboo
ensure_started "prod-bamboo"

# nginx
require_volume "nginxVolume"
ensure_started "nginx"

log "=== start-bamboo.sh complete ==="