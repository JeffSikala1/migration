#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- CONFIG ----------
USE_CUSTOM_IMAGE=1
PRIMARY_IMAGE="conexusbuildagent:local-jdk17-mvn3"
FALLBACK_IMAGE="atlassian/bamboo-agent-base:9.6.6"       # official agent image (works out of the box)
NUMBER_OF_BUILD_AGENTS="${NUMBER_OF_BUILD_AGENTS:-6}"
BAMBOO_URL="${BAMBOO_URL:-https://bamboo.mgmt.cnxs.vpcaas.fcs.gsa.gov/agentServer/}"

NETWORK_NAME="${NETWORK_NAME:-jo-iso-nw}"
NETWORK_SUBNET="${NETWORK_SUBNET:-172.25.0.0/24}"

RESTART_POLICY="${RESTART_POLICY:-on-failure:3}"
HOST_CACHE_BASE="${HOST_CACHE_BASE:-/app/cache/bamboo}"  # host path bound to each agent’s home
DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"
AGENT_SSH_HOST_DIR="${AGENT_SSH_HOST_DIR:-/app/ci-ssh}"  # contains id_argcdbb (+.pub)

# ---------- PRECHECKS ----------
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not installed on host"; exit 1; }
systemctl is-active --quiet docker || { echo "ERROR: host docker service not running"; exit 1; }
mkdir -p "$HOST_CACHE_BASE" "$AGENT_SSH_HOST_DIR"; chmod 700 "$AGENT_SSH_HOST_DIR" || true

# ---------- CHOOSE IMAGE ----------
AGENT_IMAGE="$FALLBACK_IMAGE"
if [ "$USE_CUSTOM_IMAGE" = "1" ] && docker image inspect "$PRIMARY_IMAGE" >/dev/null 2>&1; then
  echo "Using custom image: $PRIMARY_IMAGE"
  AGENT_IMAGE="$PRIMARY_IMAGE"
else
  echo "Using official image: $FALLBACK_IMAGE"
  docker image inspect "$FALLBACK_IMAGE" >/dev/null 2>&1 || docker pull "$FALLBACK_IMAGE"
fi

# ---------- NETWORK ----------
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "Creating docker network ${NETWORK_NAME} (${NETWORK_SUBNET})..."
  if [ -n "$NETWORK_SUBNET" ]; then
    docker network create -d bridge --subnet "${NETWORK_SUBNET}" "${NETWORK_NAME}" >/dev/null
  else
    docker network create -d bridge "${NETWORK_NAME}" >/dev/null
  fi
else
  echo "Network ${NETWORK_NAME} already exists."
fi

# ---------- helper: install toolchain (JDK/Maven/Docker CLI + buildx + AWS CLI v2 + kubectl) inside a running container ----------
install_tools_in() {
  local cname="$1"
  docker exec -u 0 -i "$cname" sh -lc '
    set -e
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y --no-install-recommends ca-certificates curl unzip git bash coreutils \
        openjdk-17-jdk maven iptables jq procps docker.io || true
      apt-get install -y --no-install-recommends apt-transport-https gnupg || true
      install -d -m 0755 /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true
      . /etc/os-release
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker-ce.list
      apt-get update -y || true
      apt-get install -y --no-install-recommends docker-buildx-plugin || true
    else
      (dnf -y install shadow-utils ca-certificates curl unzip git bash coreutils java-17-openjdk maven iptables nftables jq docker-cli) || true
    fi

    # AWS CLI v2
    if ! command -v aws >/dev/null 2>&1; then
      tmp="$(mktemp -d)"; trap "rm -rf $tmp" EXIT
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp/awscliv2.zip"
      unzip -q "$tmp/awscliv2.zip" -d "$tmp"
      "$tmp/aws/install" -i /usr/local/aws-cli -b /usr/local/bin || true
    fi

    # kubectl (latest stable)
    if ! command -v kubectl >/dev/null 2>&1; then
      arch="$(uname -m)"; case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; *) arch=amd64 ;; esac
      ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo v1.30.3)"
      curl -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl" -o /usr/local/bin/kubectl
      chmod +x /usr/local/bin/kubectl || true
    fi

    # Stable JAVA_HOME symlink for Bamboo capability
    if command -v java >/dev/null 2>&1; then
      jhome="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
      mkdir -p /etc/alternatives
      ln -sfn "$jhome" /etc/alternatives/java_sdk_17 || true
    fi
  '
}

# Determine host docker.sock GID for group mapping (so container can use /var/run/docker.sock)
HOST_GID="$(stat -c '%g' "$DOCKER_SOCK" 2>/dev/null || true)"
if [ -z "${HOST_GID:-}" ] || ! [[ "$HOST_GID" =~ ^[0-9]+$ ]]; then
  HOST_GID="$(docker run --rm -v "$DOCKER_SOCK":/var/run/docker.sock busybox:latest sh -c 'stat -c %g /var/run/docker.sock' 2>/dev/null || echo 0)"
fi

HOSTNAME_SHORT="$(hostname)"
# Support both Bamboo agent home paths used by different images
CONT_HOME1="/var/atlassian/application-data/bamboo-agent"
CONT_HOME2="/var/atlassian/bamboo-agent-home"

# ---------- START AGENTS ----------
for num in $(seq 1 "$NUMBER_OF_BUILD_AGENTS"); do
  NAME="${HOSTNAME_SHORT}-ba-${num}"
  HOST_HOME="${HOST_CACHE_BASE}/${NAME}"

  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  mkdir -p "${HOST_HOME}"

  # Pre-chown the host dir using the SAME image we will run
  docker run --rm -u 0 \
    -v "${HOST_HOME}:${CONT_HOME1}" \
    -v "${HOST_HOME}:${CONT_HOME2}" \
    "${AGENT_IMAGE}" bash -lc '
      id bamboo >/dev/null 2>&1 || adduser --disabled-password --gecos "" bamboo || useradd -m -s /bin/bash bamboo
      chown -R bamboo:bamboo /var/atlassian/application-data/bamboo-agent /var/atlassian/bamboo-agent-home || true
    '

  echo "Starting build agent ${NAME} with image ${AGENT_IMAGE}…"

  GID="$(stat -c '%g' "$DOCKER_SOCK")"

  if [ "$AGENT_IMAGE" = "$PRIMARY_IMAGE" ]; then
    # Custom image run path (force Java 17 + direct installer)
    docker run -d \
      --name="${NAME}" \
      --hostname="${NAME}" \
      --net="${NETWORK_NAME}" \
      --restart="${RESTART_POLICY}" \
      --group-add "${GID}" \
      -e BAMBOO_SERVER="${BAMBOO_URL}" \
      -e AGENT_NAME="${NAME}" \
      -v "${HOST_HOME}:${CONT_HOME1}" \
      -v "${HOST_HOME}:${CONT_HOME2}" \
      -v "${HOST_CACHE_BASE}:/cache/bamboo" \
      -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
      -v "${AGENT_SSH_HOST_DIR}:/home/bamboo/.ssh" \
      --entrypoint bash "${AGENT_IMAGE}" -lc '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive

        # Ensure Java 17 exists
        if ! [ -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ]; then
          apt-get update -y
          apt-get install -y --no-install-recommends openjdk-17-jre-headless ca-certificates
        fi

        # Force wrapper to use 17
        rm -rf /opt/java/openjdk || true
        ln -s /usr/lib/jvm/java-17-openjdk-amd64 /opt/java/openjdk

        # Pin wrapper.java.command (survives restarts)
        install -d -o bamboo -g bamboo /var/atlassian/application-data/bamboo-agent/conf
        CONF="/var/atlassian/application-data/bamboo-agent/conf/wrapper.conf"
        if [ -f "$CONF" ]; then
          sed -i "s#^wrapper.java.command=.*#wrapper.java.command=/opt/java/openjdk/bin/java#" "$CONF"
        else
          echo "wrapper.java.command=/opt/java/openjdk/bin/java" > "$CONF"
          chown bamboo:bamboo "$CONF"
        fi

        # Launch agent installer directly with Java 17
        exec /usr/lib/jvm/java-17-openjdk-amd64/bin/java \
          -Dbamboo.home=/var/atlassian/application-data/bamboo-agent \
          -jar /opt/atlassian/bamboo/atlassian-bamboo-agent-installer.jar \
          "$BAMBOO_SERVER"
      '
  else
    docker run -d \
      --name="${NAME}" \
      --hostname="${NAME}" \
      --net="${NETWORK_NAME}" \
      --restart="${RESTART_POLICY}" \
      --group-add "${GID}" \
      -e BAMBOO_SERVER="${BAMBOO_URL}" \
      -e AGENT_NAME="${NAME}" \
      -v "${HOST_HOME}:${CONT_HOME1}" \
      -v "${HOST_HOME}:${CONT_HOME2}" \
      -v "${HOST_CACHE_BASE}:/cache/bamboo" \
      -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
      -v "${AGENT_SSH_HOST_DIR}:/home/bamboo/.ssh" \
      --entrypoint bash "${AGENT_IMAGE}" -lc '
        set -e

        # Find a Java 17 and point /opt/java/openjdk at it
        tgt=""
        for c in /usr/lib/jvm/java-17*/bin/java; do
          [ -x "$c" ] && { tgt="${c%/bin/java}"; break; }
        done
        if [ -n "$tgt" ]; then
          mkdir -p /opt/java
          ln -sfn "$tgt" /opt/java/openjdk
        fi

        # If wrapper.conf exists, pin it to /opt/java/openjdk
        CONF="/var/atlassian/application-data/bamboo-agent/conf/wrapper.conf"
        [ -f "$CONF" ] && sed -i "s#^wrapper.java.command=.*#wrapper.java.command=/opt/java/openjdk/bin/java#" "$CONF" || true

        # Show what we’re about to use (do NOT kill the container if it’s not 17)
        if /opt/java/openjdk/bin/java -version >/tmp/jv 2>&1; then
          echo "[agent] Using $(head -1 /tmp/jv)"
        else
          echo "[agent][WARN] /opt/java/openjdk/bin/java not found or unusable; agent may try a different JRE"
        fi

        export JAVA_HOME=/opt/java/openjdk
        exec /pre-launch.sh /usr/bin/tini -- /entrypoint.py
      '
  fi

  # Tooling + docker.sock group mapping (idempotent)
  install_tools_in "${NAME}"
  docker exec -u 0 "${NAME}" bash -lc "
    set -e
    getent group '${GID}' >/dev/null 2>&1 || groupadd -g '${GID}' dockersock || true
    id -u bamboo >/dev/null 2>&1 && usermod -aG '${GID}' bamboo || true
    mkdir -p /home/bamboo/.ssh && chmod 700 /home/bamboo/.ssh && chown -R bamboo:bamboo /home/bamboo/.ssh
  "

  # Capabilities visible to Bamboo (on host)
  mkdir -p "${HOST_HOME}/bin"
  cat > "${HOST_HOME}/bin/bamboo-capabilities.properties" <<'EOF'
system.jdk.JDK\ 17=/etc/alternatives/java_sdk_17
system.builder.mvn3.Maven\ 3=/usr/share/maven
system.git.executable=/usr/bin/git
system.docker.executable=/usr/bin/docker
system.builder.command.aws=/usr/local/bin/aws
system.builder.command.kubectl=/usr/local/bin/kubectl
EOF
  chown -R root:root "${HOST_HOME}/bin"

  # Quick sanity line (optional)
  docker exec "${NAME}" bash -lc '/opt/java/openjdk/bin/java -version 2>&1 | head -1 || true' || true

  echo "Agent ${NAME} started."
done

echo "Agents running:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"