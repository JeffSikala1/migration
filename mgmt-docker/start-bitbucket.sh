#!/usr/bin/env bash

set -u
LOG_TAG="start-bitbucket"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "${SCRIPT_DIR}/lib-common.sh"

log "=== start-bitbucket.sh beginning ==="

# require the expected mountpoint and Docker volumes/networks to exist before starting anything. This is a sanity check to avoid starting against an empty root disk directory or missing volumes/networks.
require_path "/app" "docker data mount"
mountpoint -q /app || fail "/app is not a mountpoint - refusing to start"
require_volume "pgdataVolume16"
require_volume "bitbucketVolume"
require_volume "optbitbucketVolume94"
require_network "prod-net"

# Postgres
ensure_started "prod-postgres"
wait_for_postgres "prod-postgres" "postgres" 90

# Bitbucket
ensure_started "cnxs-mgmt-bitbucket"

# nginx
require_volume "nginxVolume"
ensure_started "nginx"

log "=== start-bitbucket.sh complete ==="