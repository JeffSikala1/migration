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
INSTALL_TOOLCHAIN="${INSTALL_TOOLCHAIN:-0}"

# --- JAVA HEAP FOR BAMBOO REMOTE AGENTS ---
AGENT_INIT_MEMORY="${AGENT_INIT_MEMORY:-512}"
AGENT_MAX_MEMORY="${AGENT_MAX_MEMORY:-2048}"

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
      -u 0 \
      --name="${NAME}" \
      --hostname="${NAME}" \
      --net="${NETWORK_NAME}" \
      --restart="${RESTART_POLICY}" \
      --group-add "${GID}" \
      -e BAMBOO_SERVER="${BAMBOO_URL}" \
      -e AGENT_NAME="${NAME}" \
      -e AGENT_INIT_MEMORY="${AGENT_INIT_MEMORY}" \
      -e AGENT_MAX_MEMORY="${AGENT_MAX_MEMORY}" \
      -v "${HOST_HOME}:${CONT_HOME1}" \
      -v "${HOST_HOME}:${CONT_HOME2}" \
      -v "${HOST_CACHE_BASE}:/cache/bamboo" \
      -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
      -v "${AGENT_SSH_HOST_DIR}:/home/bamboo/.ssh" \
      --entrypoint bash "${AGENT_IMAGE}" -lc '
        set -euo pipefail
        
        # Ensure bamboo user exists (if image does not have it)
        id bamboo >/dev/null 2>&1 || adduser --disabled-password --gecos "" bamboo || useradd -m -s /bin/bash bamboo

        # Force wrapper to use 17
        rm -rf /opt/java/openjdk || true
        ln -s /usr/lib/jvm/java-17-openjdk-amd64 /opt/java/openjdk
        JAVA_HOME=/opt/java/openjdk
        export JAVA_HOME
        
        # --- Import Bamboo TLS certs and configure wrapper trustStore (broker 8443 + https 443) ---
        BAMBOO_HOST="bamboo.mgmt.cnxs.vpcaas.fcs.gsa.gov"
        PASS="changeit"
        TS_DIR="/var/atlassian/application-data/bamboo-agent/conf"
        TS="${TS_DIR}/custom-truststore.jks"
        mkdir -p /tmp "$TS_DIR"

        if [ ! -f "$TS" ]; then
             echo "Creating empty truststore at $TS"
             keytool -genkeypair -alias throwaway -keystore "$TS" -storepass "$PASS" \
               -dname "CN=throwaway" -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1 || true
             keytool -delete -alias throwaway -keystore "$TS" -storepass "$PASS" >/dev/null 2>&1 || true
        fi
        chmod 644 "$TS" || true

        for PORT in 8443 443; do
          CERT_PREFIX="/tmp/bamboo-${PORT}"
          
          # Fetch and split all presented certs into separate PEM files
          rm -f "${CERT_PREFIX}"-*.pem || true
          
          # Use awk to split certificates reliably
          echo "Fetching certs from ${BAMBOO_HOST}:${PORT}..."
          openssl s_client -showcerts -connect "${BAMBOO_HOST}:${PORT}" -servername "${BAMBOO_HOST}" </dev/null 2>/dev/null \
            | awk -v prefix="${CERT_PREFIX}" "/-----BEGIN CERTIFICATE-----/ {i++; out=sprintf(\"%s-%d.pem\", prefix, i)} out {print > out} /-----END CERTIFICATE-----/ {out=\"\"}"

          if ls ${CERT_PREFIX}-*.pem 1> /dev/null 2>&1; then
             echo "Importing certs for port ${PORT}..."
             for f in ${CERT_PREFIX}-*.pem; do
                [ -s "$f" ] || continue
                CERT_ALIAS="bamboo-${PORT}-$(basename "$f" .pem)"
                # Delete if exists to avoid error
                keytool -delete -noprompt -alias "$CERT_ALIAS" -keystore "$TS" -storepass "$PASS" >/dev/null 2>&1 || true
                keytool -importcert -noprompt -alias "$CERT_ALIAS" -file "$f" -keystore "$TS" -storepass "$PASS"
             done
          else
             echo "ERROR: No certs captured from ${BAMBOO_HOST}:${PORT}"
             # We might want to exit here if strict, but lets try to proceed
          fi
        done

        # Ensure truststore permissions allow bamboo to read it
        chown bamboo:bamboo "$TS" || true
        chmod 0644 "$TS" || true

        # Pin wrapper.java.command (survives restarts)
        CONF="/var/atlassian/application-data/bamboo-agent/conf/wrapper.conf"
        mkdir -p "$(dirname "$CONF")"
        
        # Pin trustStore for the wrapper JVM (overwrite or append safely)
        # We need to act on the file carefully.
        touch "$CONF"
        
        # Helper to update-or-append wrapper property
        set_wrapper_prop() {
            local key="$1"
            local val="$2"
            local file="$3"
            if grep -q "^${key}=" "$file"; then
                sed -i "s|^${key}=.*|${key}=${val}|" "$file"
            else
                echo "${key}=${val}" >> "$file"
            fi
        }

        add_wrapper_additional() {
            local val="$1"
            local file="$2"
            local idx=1
            while grep -q "^wrapper\.java\.additional\.${idx}=" "$file"; do
                idx=$((idx+1))
            done
            echo "wrapper.java.additional.${idx}=${val}" >> "$file"
        }

        set_wrapper_prop "wrapper.java.command" "${JAVA_HOME}/bin/java" "$CONF"
        sed -i '/-Djavax.net\.ssl\.trustStorePassword=/d' "$CONF"
        sed -i '/-Djavax.net\.ssl\.trustStore=/d' "$CONF"
        add_wrapper_additional "-Djavax.net.ssl.trustStore=${TS}" "$CONF"
        add_wrapper_additional "-Djavax.net.ssl.trustStorePassword=${PASS}" "$CONF"
        # Optional SSL debug for troubleshooting (must remain sequential if enabled)
        # add_wrapper_additional "-Djavax.net.debug=ssl,handshake,trustmanager" "$CONF"

        # permission fix for entire agent home
        echo "Fixing permissions on agent home..."
        chown -R bamboo:bamboo /var/atlassian/application-data/bamboo-agent || true
        chown -R bamboo:bamboo /var/atlassian/bamboo-agent-home || true
        # Start via wrapper-managed entrypoint as BAMBOO user
        # We use su to drop privileges, ensuring the process runs as bamboo
        echo "Starting Agent..."
        exec su -p -s /bin/bash bamboo -c "export JAVA_HOME=/opt/java/openjdk; exec /pre-launch.sh /usr/bin/tini -- /entrypoint.py"
      '

    sleep 2
    if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
      echo "ERROR: $NAME is not running. Showing logs:"
      docker logs --tail 200 "$NAME" || true
      exit 1
    fi
  else
    docker run -d \
      --name="${NAME}" \
      --hostname="${NAME}" \
      --net="${NETWORK_NAME}" \
      --restart="${RESTART_POLICY}" \
      --group-add "${GID}" \
      -e BAMBOO_SERVER="${BAMBOO_URL}" \
      -e AGENT_NAME="${NAME}" \
      -e AGENT_INIT_MEMORY="${AGENT_INIT_MEMORY}" \
      -e AGENT_MAX_MEMORY="${AGENT_MAX_MEMORY}" \
      -v "${HOST_HOME}:${CONT_HOME1}" \
      -v "${HOST_HOME}:${CONT_HOME2}" \
      -v "${HOST_CACHE_BASE}:/cache/bamboo" \
      -v "${DOCKER_SOCK}:${DOCKER_SOCK}" \
      -v "${AGENT_SSH_HOST_DIR}:/home/bamboo/.ssh" \
      --entrypoint bash "${AGENT_IMAGE}" -lc '
        set -euo pipefail

        id bamboo >/dev/null 2>&1 || adduser --disabled-password --gecos "" bamboo || useradd -m -s /bin/bash bamboo

        # Find a Java 17 and point /opt/java/openjdk at it
        tgt=""
        for c in /usr/lib/jvm/java-17*/bin/java; do
          [ -x "$c" ] && { tgt="${c%/bin/java}"; break; }
        done
        if [ -n "$tgt" ]; then
          mkdir -p /opt/java
          ln -sfn "$tgt" /opt/java/openjdk
        fi

        if /opt/java/openjdk/bin/java -version >/tmp/jv 2>&1; then
          echo "[agent] Using $(head -1 /tmp/jv)"
        else
          echo "[agent][WARN] /opt/java/openjdk/bin/java not found or unusable; agent may try a different JRE"
        fi

        JAVA_HOME=/opt/java/openjdk
        export JAVA_HOME

        BAMBOO_HOST="bamboo.mgmt.cnxs.vpcaas.fcs.gsa.gov"
        PASS="changeit"
        TS_DIR="/var/atlassian/application-data/bamboo-agent/conf"
        TS="${TS_DIR}/custom-truststore.jks"
        mkdir -p /tmp "$TS_DIR"

        if [ ! -f "$TS" ]; then
          echo "Creating empty truststore at $TS"
          keytool -genkeypair -alias throwaway -keystore "$TS" -storepass "$PASS" \
            -dname "CN=throwaway" -keyalg RSA -keysize 2048 -validity 1 >/dev/null 2>&1 || true
          keytool -delete -alias throwaway -keystore "$TS" -storepass "$PASS" >/dev/null 2>&1 || true
        fi
        chmod 644 "$TS" || true

        for PORT in 8443 443; do
          CERT_PREFIX="/tmp/bamboo-${PORT}"
          rm -f "${CERT_PREFIX}"-*.pem || true
          echo "Fetching certs from ${BAMBOO_HOST}:${PORT}..."
          openssl s_client -showcerts -connect "${BAMBOO_HOST}:${PORT}" -servername "${BAMBOO_HOST}" </dev/null 2>/dev/null \
            | awk -v prefix="${CERT_PREFIX}" "/-----BEGIN CERTIFICATE-----/ {i++; out=sprintf(\"%s-%d.pem\", prefix, i)} out {print > out} /-----END CERTIFICATE-----/ {out=\"\"}"

          if ls ${CERT_PREFIX}-*.pem 1> /dev/null 2>&1; then
            echo "Importing certs for port ${PORT}..."
            for f in ${CERT_PREFIX}-*.pem; do
              [ -s "$f" ] || continue
              CERT_ALIAS="bamboo-${PORT}-$(basename "$f" .pem)"
              keytool -delete -noprompt -alias "$CERT_ALIAS" -keystore "$TS" -storepass "$PASS" >/dev/null 2>&1 || true
              keytool -importcert -noprompt -alias "$CERT_ALIAS" -file "$f" -keystore "$TS" -storepass "$PASS"
            done
          else
            echo "ERROR: No certs captured from ${BAMBOO_HOST}:${PORT}"
          fi
        done

        chown bamboo:bamboo "$TS" || true
        chmod 0644 "$TS" || true

        CONF="/var/atlassian/application-data/bamboo-agent/conf/wrapper.conf"
        mkdir -p "$(dirname "$CONF")"
        touch "$CONF"

        set_wrapper_prop() {
            local key="$1"
            local val="$2"
            local file="$3"
            if grep -q "^${key}=" "$file"; then
                sed -i "s|^${key}=.*|${key}=${val}|" "$file"
            else
                echo "${key}=${val}" >> "$file"
            fi
        }

        add_wrapper_additional() {
            local val="$1"
            local file="$2"
            local idx=1
            while grep -q "^wrapper\.java\.additional\.${idx}=" "$file"; do
                idx=$((idx+1))
            done
            echo "wrapper.java.additional.${idx}=${val}" >> "$file"
        }

        set_wrapper_prop "wrapper.java.command" "${JAVA_HOME}/bin/java" "$CONF"
        sed -i '/-Djavax.net\.ssl\.trustStorePassword=/d' "$CONF"
        sed -i '/-Djavax.net\.ssl\.trustStore=/d' "$CONF"
        add_wrapper_additional "-Djavax.net.ssl.trustStore=${TS}" "$CONF"
        add_wrapper_additional "-Djavax.net.ssl.trustStorePassword=${PASS}" "$CONF"
        chown -R bamboo:bamboo /var/atlassian/application-data/bamboo-agent || true
        chown -R bamboo:bamboo /var/atlassian/bamboo-agent-home || true

        exec su -p -s /bin/bash bamboo -c "export JAVA_HOME=/opt/java/openjdk; exec /pre-launch.sh /usr/bin/tini -- /entrypoint.py"
      '

    sleep 2
    if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
      echo "ERROR: $NAME is not running. Showing logs:"
      docker logs --tail 200 "$NAME" || true
      exit 1
    fi
  fi

  # Tooling + docker.sock group mapping (idempotent)
  if [ "${INSTALL_TOOLCHAIN}" = "1" ]; then
    install_tools_in "${NAME}"
  fi
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

  # Fix permissions on the capabilities file/dir so bamboo user can use it
  docker exec -u 0 "${NAME}" chown -R bamboo:bamboo "${CONT_HOME1}/bin" || true

  # Quick sanity line (optional)
  docker exec "${NAME}" bash -lc '/opt/java/openjdk/bin/java -version 2>&1 | head -1 || true' || true

  echo "Agent ${NAME} started."
done

echo "Agents running:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
