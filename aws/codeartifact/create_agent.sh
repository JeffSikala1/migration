#!/usr/bin/env bash
set -Eeuo pipefail

DOCKER_BUILD_AGENT_IMAGE="${DOCKER_BUILD_AGENT_IMAGE:-339713019047.dkr.ecr.us-east-1.amazonaws.com/build-agents:node22-angular19-el9-2025-09-23-1324}"
NUMBER_OF_BUILD_AGENTS="${NUMBER_OF_BUILD_AGENTS:-6}"

BAMBOO_URL="${BAMBOO_URL:-https://bamboo.mgmt.cnxs.vpcaas.fcs.gsa.gov/agentServer/}"

NETWORK_NAME="${NETWORK_NAME:-isolated_nw}"
NETWORK_SUBNET="${NETWORK_SUBNET:-172.25.0.0/24}"

HOST_CACHE_BASE="${HOST_CACHE_BASE:-/app/cache/bamboo}"
DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"

SKIP_PULL="${SKIP_PULL:-1}"

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not installed"; exit 1; }
systemctl is-active --quiet docker || { echo "ERROR: docker service not running"; exit 1; }

mkdir -p "$HOST_CACHE_BASE"

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Creating docker network $NETWORK_NAME ($NETWORK_SUBNET)..."
  docker network create -d bridge --subnet "$NETWORK_SUBNET" "$NETWORK_NAME" >/dev/null
else
  echo "Docker network $NETWORK_NAME already exists."
fi

HOSTNAME_SHORT="$(hostname)"

if [[ "$SKIP_PULL" != "1" ]]; then
  echo
  echo "Pulling build agent image..."
  docker pull "$DOCKER_BUILD_AGENT_IMAGE"
else
  echo
  echo "Skipping docker pull because SKIP_PULL=1"
  docker image inspect "$DOCKER_BUILD_AGENT_IMAGE" >/dev/null 2>&1 || {
    echo "ERROR: image not found locally: $DOCKER_BUILD_AGENT_IMAGE"
    echo "Either pull it first or run with SKIP_PULL=0"
    exit 1
  }
fi

echo
echo "Stopping/removing existing build agents..."
docker ps -aq --filter "name=${HOSTNAME_SHORT}-ba-" | xargs -r docker rm -f

echo
echo "Starting build agents..."
for num in $(seq 1 "$NUMBER_OF_BUILD_AGENTS"); do
  AGENT_NAME="${HOSTNAME_SHORT}-ba-${num}"
  AGENT_HOME="${HOST_CACHE_BASE}/${AGENT_NAME}"

  mkdir -p "$AGENT_HOME"

  docker run -d \
    --net="$NETWORK_NAME" \
    -v "${AGENT_HOME}:/cache/bamboo/${AGENT_NAME}" \
    -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
    --name="$AGENT_NAME" \
    -h "$AGENT_NAME" \
    --init \
    --restart=always \
    --sysctl net.ipv4.ip_forward=1 \
    "$DOCKER_BUILD_AGENT_IMAGE" \
    java -Dbamboo.home="/cache/bamboo/${AGENT_NAME}" -jar /opt/bamboo-agent.jar "$BAMBOO_URL"
done

echo
echo "Running Bamboo agent containers:"
docker ps --filter "name=${HOSTNAME_SHORT}-ba-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"