#!/usr/bin/env bash
# deploy-to-artifactory-and-create-bamboo-version-migrate.sh
# Deploy ONLY for long-lived PARENT branches (ll-xxx with no +child).
# Everyone else skips deploy.

set -Eeuo pipefail

normalize_url() { [[ "$1" == */ ]] && printf '%s' "$1" || printf '%s/' "$1"; }

###############################################
# Config (Bamboo / env)
###############################################
ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"
ARTIFACTORY_SEARCH_LATEST_API="${ARTIFACTORY_BASE_URL}/artifactory/api/search/latestVersion"

ARTIFACTORY_USER="${ARTIFACTORY_USER:-${bamboo_artifactory_user:-sa_bamboo}}"

# If xtrace is on, turn it off while handling secrets
xtrace_on=0
[[ $- == *x* ]] && xtrace_on=1 && set +x
ARTIFACTORY_TOKEN="${ARTIFACTORY_TOKEN:-${bamboo_artifactory_access_token_secret:-}}"
(( xtrace_on )) && set -x

LONG_LIVED_PREFIX="${LONG_LIVED_PREFIX:-ll-}"
DEFAULT_PLUGIN_REPO="${DEFAULT_PLUGIN_REPO:-conexus-plugin-repository}"
LL_PLUGIN_REPO="${LL_PLUGIN_REPO:-conexus-ll-plugin-repository}"

SNAPSHOT_REPO="${SNAPSHOT_REPO:-conexus-snapshot-local}"  # confirmed by you
SNAPSHOT_DEPLOY_REPO="${SNAPSHOT_DEPLOY_REPO:-conexus-snapshot-local}"
SNAPSHOT_DEPLOY_URL="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${SNAPSHOT_DEPLOY_REPO}")"

MAVEN_SETTINGS_OUT="${MAVEN_SETTINGS_OUT:-settings-deploy.xml}"
MAVEN_SERVER_ID="${MAVEN_SERVER_ID:-artifactory}"
NO_DEPLOY="${NO_DEPLOY:-0}"
POM_PATH="${POM_PATH:-}"
# Comma-separated short branch names allowed to deploy even if not ll-*
ALLOW_DEPLOY_BRANCHES="${ALLOW_DEPLOY_BRANCHES:-develop}"
TOKEN_PING_CHECK="${TOKEN_PING_CHECK:-1}"

###############################################
# Helpers
###############################################
die() { echo "ERROR: $*" >&2; exit 1; }

need_token() {
  [[ -n "${ARTIFACTORY_TOKEN}" ]] || die "ARTIFACTORY_TOKEN is empty. Set bamboo_artifactory_access_token_secret (or ARTIFACTORY_TOKEN)."
}

detect_branch() {
  if [[ -n "${bamboo_planRepository_branch:-}" ]]; then
    echo "${bamboo_planRepository_branch}"
    return
  fi
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

branch_short_name() {
  local ref="$1"
  echo "${ref##*/}"
}

parse_ll_parent_child() {
  local s="$1"
  local parent child
  parent="$(printf '%s' "$s" | cut -d'+' -f1)"
  child="$(printf '%s' "$s" | cut -d'+' -f2 -s || true)"
  printf '%s\n' "$parent" "$child"
}

resolve_pom_path() {
  if [[ -n "$POM_PATH" ]]; then
    [[ -f "$POM_PATH" ]] || die "POM_PATH '$POM_PATH' not found."
    echo "$POM_PATH"
    return
  fi
  [[ -f pom.xml ]] && { echo pom.xml; return; }
  local found
  found="$(find . -name pom.xml -not -path "*/target/*" | head -n1 || true)"
  [[ -n "$found" ]] || die "No pom.xml found. Run from repo root or set POM_PATH."
  echo "$found"
}

read_props() {
  local key="$1"
  awk -F= -v k="$key" '$1==k {print substr($0, index($0,$2))}' file.properties 2>/dev/null | tail -n1
}

write_settings() {
  local xtrace_on=0
  [[ $- == *x* ]] && xtrace_on=1 && set +x
  need_token

  cat > "$MAVEN_SETTINGS_OUT" <<XML
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <mirrors>
    <!-- Mirror everything to Artifactory virtual, but DO NOT mirror snapshot-local -->
    <mirror>
      <id>${MAVEN_SERVER_ID}</id>
      <mirrorOf>*,!${SNAPSHOT_DEPLOY_REPO}</mirrorOf>
      <url>${pluginRepositoryUrl}</url>
    </mirror>
  </mirrors>

  <profiles>
    <profile>
      <id>use-artifactory</id>

      <!-- Make snapshot-local reachable for SNAPSHOT deps -->
      <repositories>
        <repository>
          <id>${SNAPSHOT_DEPLOY_REPO}</id>
          <url>${mavenFeatureRepositoryUrl}</url>
          <releases><enabled>false</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>
      </repositories>

      <pluginRepositories>
        <pluginRepository>
          <id>${SNAPSHOT_DEPLOY_REPO}</id>
          <url>${mavenFeatureRepositoryUrl}</url>
          <releases><enabled>false</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>use-artifactory</activeProfile>
  </activeProfiles>

  <servers>
    <server>
      <id>${MAVEN_SERVER_ID}</id>
      <username>${ARTIFACTORY_USER}</username>
      <password>${ARTIFACTORY_TOKEN}</password>
    </server>
    <server>
      <id>${SNAPSHOT_DEPLOY_REPO}</id>
      <username>${ARTIFACTORY_USER}</username>
      <password>${ARTIFACTORY_TOKEN}</password>
    </server>
  </servers>
</settings>
XML

  (( xtrace_on )) && set -x
  echo "Wrote ${MAVEN_SETTINGS_OUT} (server id=${MAVEN_SERVER_ID})"
}

write_latest_version_property() {
  local repo="$1"
  local g="${buildVersionQueryGroup:-}"
  local a="${buildVersionQueryArtifact:-}"
  local v="${mavenVersion:-}"

  if [[ -z "$g" || -z "$a" ]]; then
    echo "Skipping latestVersion: buildVersionQueryGroup/buildVersionQueryArtifact not provided."
    return 0
  fi

  local xtrace_on=0
  [[ $- == *x* ]] && xtrace_on=1 && set +x
  need_token

  local url="${ARTIFACTORY_SEARCH_LATEST_API}?g=${g}&a=${a}"
  [[ -n "$v" ]] && url="${url}&v=${v}"
  url="${url}&repos=${repo}"

  echo "Query latestVersion: $url"
  local lv
  lv="$(curl -sSk -H "Authorization: Bearer ${ARTIFACTORY_TOKEN}" "$url" || true)"
  (( xtrace_on )) && set -x

  if [[ -n "$lv" && "$lv" != "null" ]]; then
    grep -v '^latestVersion=' file.properties > file.properties.tmp || true
    mv file.properties.tmp file.properties
    echo "latestVersion=$lv" >> file.properties
    echo "latestVersion=$lv"
  else
    echo "latestVersion not resolved (empty response)."
  fi
}

preflight_token_ping() {
  (( TOKEN_PING_CHECK )) || return 0

  echo "TOKEN_PING_CHECK=1 -> verifying Artifactory token connectivity..."

  local xtrace_on=0
  [[ $- == *x* ]] && xtrace_on=1 && set +x

  need_token

  local ping
  ping="$(curl -sk -H "Authorization: Bearer ${ARTIFACTORY_TOKEN}" "${ARTIFACTORY_BASE_URL}/artifactory/api/system/ping" || true)"

  (( xtrace_on )) && set -x

  [[ "$ping" == "OK" ]] || die "Artifactory token ping failed (expected OK, got '${ping:-<empty>}')."
  echo "Artifactory token ping: OK"
}

###############################################
# Main
###############################################
BranchRef="$(detect_branch)"
BranchName="$(branch_short_name "$BranchRef")"

echo "BranchRef=$BranchRef"
echo "BranchName=$BranchName"

IS_LL=false
if [[ "${BranchName:0:${#LONG_LIVED_PREFIX}}" == "$LONG_LIVED_PREFIX" ]]; then
  IS_LL=true
fi

touch file.properties

pluginRepositoryUrl="$(read_props pluginRepositoryUrl || true)"
mavenFeatureRepositoryUrl="$(read_props mavenFeatureRepositoryUrl || true)"

# Fallback URLs if file.properties wasn't pre-populated
if [[ -z "${pluginRepositoryUrl}" || -z "${mavenFeatureRepositoryUrl}" ]]; then
  if [[ "$IS_LL" == true ]]; then
    mapfile -t ll_parts < <(parse_ll_parent_child "$BranchName")
    ParentBranchName="${ll_parts[0]}"
    ChildBranchName="${ll_parts[1]:-}"
    pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${LL_PLUGIN_REPO}")"
    mavenFeatureRepositoryUrl="${SNAPSHOT_DEPLOY_URL}"
  else
    pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${DEFAULT_PLUGIN_REPO}")"
    mavenFeatureRepositoryUrl="${SNAPSHOT_DEPLOY_URL}"
  fi
fi

# Write clean properties every run
if [[ "$IS_LL" == true ]]; then
  mapfile -t ll_parts < <(parse_ll_parent_child "$BranchName")
  ParentBranchName="${ll_parts[0]}"
  ChildBranchName="${ll_parts[1]:-}"
  mavenFeatureRepositoryUrl="${SNAPSHOT_DEPLOY_URL}"
  cat > file.properties <<EOF
BranchName=${ParentBranchName}
ChildBranchName=${ChildBranchName}
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=true
EOF
else
  cat > file.properties <<EOF
BranchName=${BranchName}
ChildBranchName=
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=false
EOF
fi

echo "contents of file.properties"
cat file.properties

preflight_token_ping

write_settings

###############################################
# DEPLOY GATE:
# - allow LL parent branches (existing behavior)
# - ALSO allow specific branches (default: develop)
###############################################

# helper: check if BranchName is in comma-separated allowlist
branch_is_allowed() {
  local list="$1"
  local b="$2"
  local IFS=',' item
  for item in $list; do
    item="${item// /}"
    [[ -n "$item" && "$b" == "$item" ]] && return 0
  done
  return 1
}

DEPLOY_ALLOWED=false

if [[ "$IS_LL" == true ]]; then
  # LL branches: only deploy from the PARENT (no "+child")
  if [[ -z "${ChildBranchName:-}" ]]; then
    DEPLOY_ALLOWED=true
  else
    echo "Long-lived CHILD branch → SKIPPING deploy (legacy behavior)."
  fi
else
  # Non-LL branches: allow deploy on allowlisted branches (e.g., develop)
  if branch_is_allowed "$ALLOW_DEPLOY_BRANCHES" "$BranchName"; then
    DEPLOY_ALLOWED=true
    # ParentBranchName is used later in mvn args; set it for non-LL deploy branches
    ParentBranchName="$BranchName"
    ChildBranchName=""
  else
    echo "Non long-lived branch → SKIPPING deploy (per current policy)."
  fi
fi

if [[ "$DEPLOY_ALLOWED" != true ]]; then
  exit 0
fi

# For any allowed deploy (LL parent or develop), deploy to snapshot-local
mavenFeatureRepositoryUrl="${SNAPSHOT_DEPLOY_URL}"

echo "Deploy enabled on '${BranchName}' → deploying to ${mavenFeatureRepositoryUrl}"

if (( NO_DEPLOY )); then
  echo "NO_DEPLOY=1 → skipping mvn deploy"
else
  POM_TO_USE="$(resolve_pom_path)"
  mvn -B -U -s "$MAVEN_SETTINGS_OUT" -f "$POM_TO_USE" deploy -DskipTests=true \
    -Dbamboo.inject.BranchName="${ParentBranchName}" \
    -Dbamboo.inject.mavenFeatureRepositoryUrl="${mavenFeatureRepositoryUrl}" \
    -Dbamboo.inject.pluginRepositoryUrl="${pluginRepositoryUrl}" \
    -DaltDeploymentRepository="${MAVEN_SERVER_ID}::default::${mavenFeatureRepositoryUrl}"
fi

# Keep legacy “latestVersion” output; choose one:
# Option 1 (legacy LL parent): resolve in the parent repo itself
write_latest_version_property "${SNAPSHOT_DEPLOY_REPO}"

# Option 2 (if you ever want): resolve against snapshot repo instead
# write_latest_version_property "${SNAPSHOT_DEPLOY_REPO}"

echo
echo "FINAL file.properties"
cat file.properties