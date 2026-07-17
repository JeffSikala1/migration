#!/usr/bin/env bash

set -u
LOG_TAG="start-artifactory"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "${SCRIPT_DIR}/lib-common.sh"

log "=== start-artifactory.sh beginning ==="

# require the expected mountpoint and Docker volumes/networks to exist before starting anything. This is a sanity check to avoid starting against an empty root disk directory or missing volumes/networks.
require_path "/app/postgres/data" "artifactory-postgres data directory"
require_path "/app/jfrog/artifactory/var" "artifactory data directory"
require_path "/app/jfrog/artifactory/security" "artifactory security/certs directory"
require_path "/app/jfrog/artifactory/var/data/nginx" "artifactory-nginx data directory"
require_network "prod-net"

# Postgres
ensure_started "artifactory-postgres"
wait_for_postgres "artifactory-postgres" "artifactory" 90

# Artifactory app
ensure_started "artifactory"

# artifactory nginx
ensure_started "artifactory-nginx"

log "=== start-artifactory.sh complete ==="