#!/usr/bin/env bash
set -euo pipefail

# ---------- CONFIG ----------
PRIMARY_IMAGE="conexusbuildagent:local-jdk17-mvn3"      # your local image (fallback used if missing)
FALLBACK_IMAGE="atlassian/bamboo-agent-base:latest"
NUMBER_OF_BUILD_AGENTS=6
BAMBOO_URL="https://bamboo.mgmt.cnxs.vpcaas.fcs.gsa.gov/agentServer/"

NETWORK_NAME="isolated_nw"
NETWORK_SUBNET="172.25.0.0/24"

RESTART_POLICY="on-failure:3"
SYSCTL_FORWARD="net.ipv4.ip_forward=1"

HOST_CACHE_BASE="/app/cache/bamboo"                     # host path bound to each agent's home
DOCKER_SOCK="/var/run/docker.sock"

# Angular / Node requirements
NODE_MAJOR=20
ANGULAR_CLI_VERSION="19.2.17"

# ---------- PRECHECKS ----------
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not installed."; exit 1; }
systemctl is-active --quiet docker || { echo "ERROR: docker is not active."; exit 1; }

# ---------- CHOOSE IMAGE ----------
AGENT_IMAGE="$PRIMARY_IMAGE"
USE_FALLBACK=0
if ! docker image inspect "$PRIMARY_IMAGE" >/dev/null 2>&1; then
  echo "NOTE: $PRIMARY_IMAGE not found locally. Using fallback: $FALLBACK_IMAGE"
  AGENT_IMAGE="$FALLBACK_IMAGE"
  USE_FALLBACK=1
  docker image inspect "$FALLBACK_IMAGE" >/dev/null 2>&1 || docker pull "$FALLBACK_IMAGE"
fi

# ---------- NETWORK (idempotent) ----------
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "Creating docker network ${NETWORK_NAME} (${NETWORK_SUBNET})..."
  docker network create -d bridge --subnet "${NETWORK_SUBNET}" "${NETWORK_NAME}" >/dev/null
else
  echo "Network ${NETWORK_NAME} already exists."
fi

# ---------- helper: install toolchain inside the container ----------
install_tools_in() {
  local cname="$1"
  docker exec -i "$cname" bash -lc "
    set -e

    # --- Base tools (Debian/Ubuntu vs RHEL-like) ---
    if command -v apt-get >/dev/null 2>&1; then
      need_update=0
      for pkg in openjdk-17-jdk maven git ca-certificates curl unzip gnupg; do
        dpkg -s \"\$pkg\" >/dev/null 2>&1 || need_update=1
      done
      if [ \"\$need_update\" -eq 1 ]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          openjdk-17-jdk maven git ca-certificates curl unzip gnupg
        rm -rf /var/lib/apt/lists/*
      fi

      # --- Node.js ${NODE_MAJOR} (NodeSource) ---
      if ! command -v node >/dev/null 2>&1 || [ \"\$(node -v 2>/dev/null | sed 's/v//;s/\\..*//')\" -lt ${NODE_MAJOR} ]; then
        curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
      fi

    else
      # RHEL-like fallback
      (yum -y install java-17-openjdk maven git curl unzip ca-certificates gnupg \
        || dnf -y install java-17-openjdk maven git curl unzip ca-certificates gnupg) || true
      if ! command -v node >/dev/null 2>&1 || [ \"\$(node -v 2>/dev/null | sed 's/v//;s/\\..*//')\" -lt ${NODE_MAJOR} ]; then
        curl -fsSL https://rpm.nodesource.com/setup_${NODE_MAJOR}.x | bash -
        (yum -y install nodejs || dnf -y install nodejs)
      fi
    fi

    # --- Angular CLI ${ANGULAR_CLI_VERSION} (idempotent) ---
    npm config set fund false >/dev/null 2>&1 || true
    npm config set audit false >/dev/null 2>&1 || true
    if ! command -v ng >/dev/null 2>&1; then
      npm i -g @angular/cli@${ANGULAR_CLI_VERSION}
    else
      CURRENT=\$(ng version --version 2>/dev/null | head -n1 || true)
      if [ \"\${CURRENT}\" != \"${ANGULAR_CLI_VERSION}\" ]; then
        npm i -g @angular/cli@${ANGULAR_CLI_VERSION}
      fi
    fi

    # --- AWS CLI v2 (official installer; idempotent) ---
    if ! command -v aws >/dev/null 2>&1; then
      tmpdir=\$(mktemp -d)
      curl -sSL \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"\$tmpdir/awscliv2.zip\"
      unzip -q \"\$tmpdir/awscliv2.zip\" -d \"\$tmpdir\"
      \"\$tmpdir/aws/install\" -i /usr/local/aws-cli -b /usr/local/bin
      rm -rf \"\$tmpdir\"
    fi

    # --- Ensure Bamboo-friendly JDK 17 path via alternatives ---
    JAVA_BIN=\$(command -v java)
    JAVA_HOME=\$(dirname \$(dirname \$(readlink -f \"\$JAVA_BIN\")))
    mkdir -p /etc/alternatives
    ln -sfn \"\$JAVA_HOME\" /etc/alternatives/java_sdk_17

    # Sanity (will print to container logs)
    echo '--- tool versions ---'
    java -version
    mvn -v
    node -v
    npm -v
    ng version --version || true
    aws --version
  "
}

# ---------- START AGENTS ----------
HOSTNAME_SHORT="$(hostname)"
for num in $(seq 1 "${NUMBER_OF_BUILD_AGENTS}"); do
  NAME="${HOSTNAME_SHORT}-ba-${num}"
  CONT_CACHE="/var/atlassian/bamboo-agent-home"
  HOST_CACHE="${HOST_CACHE_BASE}/${NAME}"

  mkdir -p "${HOST_CACHE}"; chown root:root "${HOST_CACHE}"; chmod 755 "${HOST_CACHE}"
  docker rm -f "${NAME}" >/dev/null 2>&1 || true

  echo "Starting build agent ${NAME} with image ${AGENT_IMAGE}..."
  docker run -d \
    --name="${NAME}" \
    --hostname="${NAME}" \
    --net="${NETWORK_NAME}" \
    --restart="${RESTART_POLICY}" \
    --init \
    --sysctl "${SYSCTL_FORWARD}" \
    -e "BAMBOO_SERVER=${BAMBOO_URL}" \
    -e "AGENT_NAME=${NAME}" \
    -v "${HOST_CACHE}:${CONT_CACHE}" \
    -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
    "${AGENT_IMAGE}"

  # Install full toolchain in-place (idempotent)
  install_tools_in "${NAME}"

  # Ensure Bamboo always sees the capabilities (host-side file in agent home)
  sudo mkdir -p "${HOST_CACHE}/bin"
  sudo tee "${HOST_CACHE}/bin/bamboo-capabilities.properties" >/dev/null <<'EOF'
system.jdk.JDK\ 17=/etc/alternatives/java_sdk_17
system.builder.mvn3.Maven\ 3=/usr/share/maven
system.builder.node.Node.js=/usr/bin/node
angular.cli=/usr/bin/ng
awscli=/usr/local/bin/aws
EOF
  sudo chown -R root:root "${HOST_CACHE}/bin"

  # Restart once so the agent reloads the capabilities file fast
  docker restart "${NAME}" >/dev/null
done

echo "Agents launched:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"