#!/usr/bin/env bash


LOG_TAG="${LOG_TAG:-atlassian-startup}"

log() {
  echo "[$(date -Iseconds)] ${LOG_TAG}: $*"
  logger -t "$LOG_TAG" "$*" 2>/dev/null || true
}

fail() {
  log "FAIL: $*"
  exit 1
}


# requires the path to exist, otherwise fails with an error message.
require_path() {
  local path="$1" desc="${2:-$1}"
  if [ ! -e "$path" ]; then
    fail "$desc ($path) does not exist - refusing to start. Investigate before proceeding (wrong host? disk not mounted? path renamed?)."
  fi
  log "OK: $desc exists at $path"
}

# requires the named Docker volume to exist, otherwise fails with an error message.
require_volume() {
  local vol="$1"
  if ! docker volume inspect "$vol" >/dev/null 2>&1; then
    fail "Expected Docker volume '$vol' is missing - refusing to start."
  fi
  log "OK: volume '$vol' exists"
}

# requires the named Docker network to exist, otherwise fails with an error message.
require_network() {
  local net="$1"
  if ! docker network inspect "$net" >/dev/null 2>&1; then
    fail "Expected Docker network '$net' is missing - refusing to start."
  fi
  log "OK: network '$net' exists"
}

# checks if a container with the given name exists. Returns 0 if it exists, 1 otherwise.
container_exists() {
  docker container inspect "$1" >/dev/null 2>&1
}

# checks if a container with the given name is running. Returns 0 if it is running, 1 otherwise.
container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# ensures that the container with the given name is started. Fails if the container does not exist.
ensure_started() {
  local name="$1"
  if ! container_exists "$name"; then
    fail "Container '$name' does not exist on this host - refusing to create a new one automatically. If this is expected (e.g. a real upgrade), start it manually per the runbook."
  fi
  if container_running "$name"; then
    log "OK: '$name' is already running"
  else
    log "Starting '$name'..."
    docker start "$name" >/dev/null
    sleep 2
    if container_running "$name"; then
      log "OK: '$name' started"
    else
      fail "'$name' did not come up after 'docker start' - check 'docker logs $name'"
    fi
  fi
}

# waits for the Postgres instance in the given container to accept connections. Fails if it doesn't become ready within the specified timeout (default 90 seconds).
wait_for_postgres() {
  local container="$1" user="$2" timeout="${3:-90}"
  local waited=0
  log "Waiting for Postgres in '$container' to accept connections (timeout ${timeout}s)..."
  while ! docker exec "$container" pg_isready -U "$user" >/dev/null 2>&1; do
    sleep 3
    waited=$((waited + 3))
    if [ "$waited" -ge "$timeout" ]; then
      fail "Postgres in '$container' did not become ready within ${timeout}s - check 'docker logs $container'"
    fi
  done
  log "OK: Postgres in '$container' is ready (waited ${waited}s)"
}