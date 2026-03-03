#!/usr/bin/env bash
# deploy-to-artifactory-skip-bamboo-version-migrate.sh
# Artifactory version (not CodeArtifact).
# Deploys for:
#   - Long-lived PARENT branches (ll-xxx with no +child)
#   - allowlisted branches (default: develop)
# Skips:
#   - Long-lived CHILD branches
#   - other feature branches

set -Eeuo pipefail

###############################################
# Config (Bamboo / env)
###############################################
ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"
ARTIFACTORY_USER="${ARTIFACTORY_USER:-${bamboo_artifactory_user:-sa_bamboo}}"

# Turn off xtrace while handling secrets
xtrace_on=0
[[ $- == *x* ]] && xtrace_on=1 && set +x
ARTIFACTORY_TOKEN="${ARTIFACTORY_TOKEN:-${bamboo_artifactory_access_token_secret:-}}"
(( xtrace_on )) && set -x

LONG_LIVED_PREFIX="${LONG_LIVED_PREFIX:-ll-}"
DEFAULT_PLUGIN_REPO="${DEFAULT_PLUGIN_REPO:-conexus-plugin-repository}"
LL_PLUGIN_REPO="${LL_PLUGIN_REPO:-conexus-ll-plugin-repository}"
SNAPSHOT_DEPLOY_REPO="${SNAPSHOT_DEPLOY_REPO:-conexus-snapshot-local}"

MAVEN_SETTINGS_OUT="${MAVEN_SETTINGS_OUT:-settings-artifactory.xml}"
MAVEN_SERVER_ID="${MAVEN_SERVER_ID:-artifactory}"  # keep consistent with mirror + deploy id
NO_DEPLOY="${NO_DEPLOY:-0}"
POM_PATH="${POM_PATH:-}"

# Comma-separated short branch names allowed to deploy even if not ll-*
ALLOW_DEPLOY_BRANCHES="${ALLOW_DEPLOY_BRANCHES:-develop}"

###############################################
# Helpers
###############################################
die() { echo "ERROR: $*" >&2; exit 1; }

need_token() {
  [[ -n "${ARTIFACTORY_TOKEN}" ]] || die "ARTIFACTORY_TOKEN is empty."
}

normalize_url() { [[ "$1" == */ ]] && printf '%s' "$1" || printf '%s/' "$1"; }

detect_branch() {
  if [[ -n "${bamboo_planRepository_branch:-}" ]]; then
    echo "${bamboo_planRepository_branch}"
  else
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
  fi
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
    echo "$POM_PATH"; return
  fi
  [[ -f pom.xml ]] && { echo pom.xml; return; }
  local found
  found="$(find . -name pom.xml -not -path "*/target/*" | head -n1 || true)"
  [[ -n "$found" ]] || die "No pom.xml found."
  echo "$found"
}

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

write_settings() {
  need_token

  local xtrace_on=0
  [[ $- == *x* ]] && xtrace_on=1 && set +x

  cat > "$MAVEN_SETTINGS_OUT" <<XML
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <mirrors>
    <!-- Mirror EVERYTHING to our Artifactory virtual, EXCEPT snapshot-local -->
    <mirror>
      <id>${MAVEN_SERVER_ID}</id>
      <mirrorOf>*,!${SNAPSHOT_DEPLOY_REPO}</mirrorOf>
      <url>${pluginRepositoryUrl}</url>
    </mirror>
  </mirrors>

  <profiles>
    <profile>
      <id>use-artifactory</id>

      <!-- Ensure snapshot-local is reachable for SNAPSHOT deps -->
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
  echo "Wrote ${MAVEN_SETTINGS_OUT}"
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

SNAPSHOT_URL="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${SNAPSHOT_DEPLOY_REPO}")"

DEPLOY_ALLOWED=false
ParentBranchName="$BranchName"
ChildBranchName=""

if [[ "$IS_LL" == true ]]; then
  mapfile -t ll_parts < <(parse_ll_parent_child "$BranchName")
  ParentBranchName="${ll_parts[0]}"
  ChildBranchName="${ll_parts[1]:-}"

  pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${LL_PLUGIN_REPO}")"
  mavenFeatureRepositoryUrl="$SNAPSHOT_URL"

  if [[ -z "${ChildBranchName:-}" ]]; then
    DEPLOY_ALLOWED=true
  else
    echo "Long-lived CHILD branch → NOT deploying (legacy behavior)."
  fi

  cat > file.properties <<EOF
BranchName=${ParentBranchName}
ChildBranchName=${ChildBranchName}
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=true
EOF
else
  pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${DEFAULT_PLUGIN_REPO}")"
  mavenFeatureRepositoryUrl="$SNAPSHOT_URL"

  if branch_is_allowed "$ALLOW_DEPLOY_BRANCHES" "$BranchName"; then
    DEPLOY_ALLOWED=true
  else
    echo "Feature/other branch → NOT deploying (policy)."
  fi

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

write_settings

###############################################
# DEPLOY
###############################################
if [[ "$DEPLOY_ALLOWED" != true ]]; then
  exit 0
fi

echo "Deploy enabled on '${BranchName}' → deploying to ${mavenFeatureRepositoryUrl}"

if (( NO_DEPLOY )); then
  echo "NO_DEPLOY=1 → skipping mvn deploy"
else
  POM_TO_USE="$(resolve_pom_path)"
  mvn -B -U -s "$MAVEN_SETTINGS_OUT" -f "$POM_TO_USE" deploy -DskipTests=true \
    -Dbamboo.inject.BranchName="${ParentBranchName}" \
    -Dbamboo.inject.mavenFeatureRepositoryUrl="${mavenFeatureRepositoryUrl}" \
    -Dbamboo.inject.pluginRepositoryUrl="${pluginRepositoryUrl}" \
    -DaltDeploymentRepository="${MAVEN_SERVER_ID}::${mavenFeatureRepositoryUrl}"
fi

echo
echo "FINAL file.properties"
cat file.properties
echo