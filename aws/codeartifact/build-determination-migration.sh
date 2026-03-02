#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (Bamboo variables)
# =========================
ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"

# Use an access token from Bamboo global vars (preferred).
# Example Bamboo var name: bamboo_artifactory_access_token_secret
ACCESS_TOKEN="${bamboo_artifactory_access_token_secret:-}"

# Legacy behavior knobs
LONG_LIVED_PREFIX="ll-"
DEFAULT_PLUGIN_REPO="conexus-plugin-repository"
LL_PLUGIN_REPO="conexus-ll-plugin-repository"

# If true, script will create a Maven local repo per long-lived branch (like legacy).
CREATE_LL_REPO="${CREATE_LL_REPO:-false}"

# =========================
# Derived endpoints
# =========================
REPO_API="${ARTIFACTORY_BASE_URL}/artifactory/api/repositories"
PERM_API="${ARTIFACTORY_BASE_URL}/artifactory/api/v2/security/permissions"

# =========================
# Helpers
# =========================
die() { echo "ERROR: $*" >&2; exit 1; }

auth_header() {
  # If you ever need to support API key again, you can extend this.
  [[ -n "${ACCESS_TOKEN}" ]] || die "ACCESS_TOKEN is empty. Set bamboo_artifactory_access_token_secret in Bamboo."
  echo "Authorization: Bearer ${ACCESS_TOKEN}"
}

normalize_url() { [[ "$1" == */ ]] && echo "$1" || echo "$1/"; }

detect_branch() {
  # Bamboo vars first, then git
  if [[ -n "${bamboo_planRepository_branch:-}" ]]; then
    echo "${bamboo_planRepository_branch}"
  else
    git rev-parse --abbrev-ref HEAD 2>/dev/null | cut -d'/' -f2
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

# Optional: update permission targets (ONLY if you still do this in the new world)
# If Okta/SailPoint will handle perms, leave this disabled.
append_repo_to_permission() {
  local perm="$1" repo="$2"

  curl -sS -H "$(auth_header)" "${PERM_API}/${perm}" \
    | jq ".repo.repositories += [\"${repo}\"] | .repo.repositories |= unique" \
    | curl -sS -X PUT -H "$(auth_header)" -H "Content-Type: application/json" \
        "${PERM_API}/${perm}" -d @- >/dev/null
}

# =========================
# Main
# =========================
BranchName="$(detect_branch)"
BranchName="${BranchName#refs/heads/}"
BranchName="${BranchName#*/}"
echo "BranchName=${BranchName}"

IS_LL=false
if [[ "${BranchName:0:3}" == "${LONG_LIVED_PREFIX}" ]]; then
  IS_LL=true
fi

if [[ "$IS_LL" == true ]]; then
  echo "This is a long lived branch"

  ParentBranchName="$(echo "$BranchName" | cut -d'+' -f1)"
  ChildBranchName="$(echo "$BranchName" | cut -d'+' -f2 -s || true)"

  # Truncate file before writing properties
  : > file.properties

  pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${LL_PLUGIN_REPO}")"
  mavenFeatureRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/conexus-snapshot-local")"

  cat > file.properties <<EOF
BranchName=${ParentBranchName}
ChildBranchName=${ChildBranchName}
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=${IS_LL}
EOF

  # Create per-branch Maven repo if missing (legacy-style), only if allowed
  if [[ "${CREATE_LL_REPO}" == "true" ]]; then
    if repo_exists "${ParentBranchName}"; then
      echo "Repo '${ParentBranchName}' already exists."
    else
      create_maven_repo "${ParentBranchName}"

      # OPTIONAL: only do this if you're still managing perms this way
      # append_repo_to_permission "anon_read_only" "${ParentBranchName}"
      # append_repo_to_permission "uploadOnly" "${ParentBranchName}"
    fi
  else
    echo "CREATE_LL_REPO=false; skipping repo creation."
  fi

else
  echo "Not a long lived branch"

  # Truncate file before writing properties
  : > file.properties

  pluginRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/${DEFAULT_PLUGIN_REPO}")"
  mavenFeatureRepositoryUrl="$(normalize_url "${ARTIFACTORY_BASE_URL}/artifactory/conexus-snapshot-local")"

  ParentBranchName="${BranchName}"
  ChildBranchName=""

  cat > file.properties <<EOF
BranchName=${ParentBranchName}
ChildBranchName=${ChildBranchName}
pluginRepositoryUrl=${pluginRepositoryUrl}
mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}
isLongLived=${IS_LL}
EOF
fi

echo "Wrote file.properties:"
cat file.properties