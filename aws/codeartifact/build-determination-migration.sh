#!/usr/bin/env bash
set -euo pipefail

ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"
ACCESS_TOKEN="${bamboo_artifactory_access_token_secret:-}"

LONG_LIVED_PREFIX="ll-"
DEFAULT_PLUGIN_REPO="conexus-plugin-repository"
LL_PLUGIN_REPO="conexus-ll-plugin-repository"
CREATE_LL_REPO="${CREATE_LL_REPO:-false}"

REPO_API="${ARTIFACTORY_BASE_URL}/artifactory/api/repositories"
PERM_API="${ARTIFACTORY_BASE_URL}/artifactory/api/v2/security/permissions"

die() { echo "ERROR: $*" >&2; exit 1; }

auth_header() {
  [[ -n "${ACCESS_TOKEN}" ]] || die "ACCESS_TOKEN is empty. Set bamboo_artifactory_access_token_secret in Bamboo."
  echo "Authorization: Bearer ${ACCESS_TOKEN}"
}

normalize_url() { [[ "$1" == */ ]] && echo "$1" || echo "$1/"; }

detect_branch() {
  if [[ -n "${bamboo_planRepository_branch:-}" ]]; then
    echo "${bamboo_planRepository_branch}"
  else
    git rev-parse --abbrev-ref HEAD 2>/dev/null
  fi
}

repo_exists() {
  local repo="$1"
  curl -sS -o /dev/null -w "%{http_code}" \
    -H "$(auth_header)" \
    "${REPO_API}/${repo}" | grep -qE '^(200|302)$'
}

create_maven_repo() {
  local repo="$1"
  echo "Creating Maven repo: ${repo}"

  curl -sS -X PUT \
    -H "Content-Type: application/json" \
    -H "$(auth_header)" \
    "${REPO_API}/${repo}" \
    -d '{
      "key": "'${repo}'",
      "rclass": "local",
      "packageType": "maven",
      "repoLayoutRef": "maven-2-default",
      "snapshotVersionBehavior": "unique"
    }' >/dev/null
}

RawBranchName="$(detect_branch)"
RawBranchName="${RawBranchName#refs/heads/}"

BranchName="${RawBranchName}"
ParentBranchName="${RawBranchName}"
ChildBranchName=""

# Only collapse feature/ll-* to ll-* if that is intentional
if [[ "${RawBranchName}" == feature/ll-* ]]; then
  ParentBranchName="${RawBranchName#feature/}"
  BranchName="${ParentBranchName}"
fi

echo "RawBranchName=${RawBranchName}"
echo "BranchName=${BranchName}"

IS_LL=false
if [[ "${BranchName}" == ${LONG_LIVED_PREFIX}* ]]; then
  IS_LL=true
fi

: > file.properties

if [[ "$IS_LL" == true ]]; then
  echo "This is a long lived branch"

  if [[ "${BranchName}" == *"+"* ]]; then
    ParentBranchName="$(echo "$BranchName" | cut -d'+' -f1)"
    ChildBranchName="$(echo "$BranchName" | cut -d'+' -f2 -s || true)"
  else
    ParentBranchName="${BranchName}"
  fi

  pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${LL_PLUGIN_REPO}")"
  mavenFeatureRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/conexus-snapshot-local")"

  cat > file.properties <<EOF
RawBranchName=${RawBranchName}
BranchName=${BranchName}
ParentBranchName=${ParentBranchName}
ChildBranchName=${ChildBranchName}
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=${IS_LL}
EOF

  if [[ "${CREATE_LL_REPO}" == "true" ]]; then
    if repo_exists "${ParentBranchName}"; then
      echo "Repo '${ParentBranchName}' already exists."
    else
      create_maven_repo "${ParentBranchName}"
    fi
  else
    echo "CREATE_LL_REPO=false; skipping repo creation."
  fi
else
  echo "Not a long lived branch"

  pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${DEFAULT_PLUGIN_REPO}")"
  mavenFeatureRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/conexus-snapshot-local")"

  cat > file.properties <<EOF
RawBranchName=${RawBranchName}
BranchName=${BranchName}
ParentBranchName=${ParentBranchName}
ChildBranchName=${ChildBranchName}
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=${IS_LL}
EOF
fi

echo "Wrote file.properties:"
cat file.properties
