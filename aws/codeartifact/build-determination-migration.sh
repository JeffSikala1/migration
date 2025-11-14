#!/usr/bin/env bash
# build-determination.sh
# Purpose: pick the correct AWS CodeArtifact Maven repo for this branch,
#          write endpoints to file.properties for downstream steps,
#          and generate a Maven settings file (settings-ca.xml) with
#          a mirror and short-lived auth token.

set -Eeuo pipefail
# Added: allow sourcing as a library
if [ "${1:-}" = "--lib" ]; then
  # Loaded as a library: define helpers only, skip main execution
  return 0 2>/dev/null || exit 0
fi

###############################################
# Configuration (override via environment)
###############################################
CA_REGION="${CA_REGION:-us-east-1}"
CA_DOMAIN="${CA_DOMAIN:-cnxsartifact}"
CA_ACCOUNT="${CA_ACCOUNT:-339713019047}"

# Branch naming convention from legacy system
LONG_LIVED_PREFIX="${LONG_LIVED_PREFIX:-LL}"

# Default aggregator (acts like a virtual repo in JFrog)
DEFAULT_VIRTUAL_REPO="${DEFAULT_VIRTUAL_REPO:-conexus-plugin-repository}"

# Create the per-LL branch repo if it's missing
CREATE_LL_REPO="${CREATE_LL_REPO:-true}"

# Also write settings-ca.xml (set to 0 if your plan provides it separately)
WRITE_MAVEN_SETTINGS="${WRITE_MAVEN_SETTINGS:-1}"

# Treat branches as long-lived if they match this regex (case-insensitive)
# Defaults: main, master, release/*, hotfix/*, or any branch that contains "/ll-"
LONG_LIVED_REGEX="${LONG_LIVED_REGEX:-^(main|master|release/.*|hotfix/.*|.*(/|^)ll-.*)$}"

# Optional hard override (true/false) – allows forcing behavior without code changes
FORCE_LONG_LIVED="${FORCE_LONG_LIVED:-}"

###############################################
# Helpers
###############################################
aws_ca() {
  # Uses environment-provided AWS credentials/role
  aws --region "$CA_REGION" ${AWS_PROFILE:+--profile "$AWS_PROFILE"} codeartifact "$@"
}

endpoint_for_repo() {
  local repo="$1"
  aws_ca get-repository-endpoint \
    --domain "$CA_DOMAIN" \
    --repository "$repo" \
    --format maven \
    --query repositoryEndpoint \
    --output text
}

repo_exists() {
  local repo="$1"
  aws_ca describe-repository --domain "$CA_DOMAIN" --repository "$repo" >/dev/null 2>&1
}

ensure_repo_exists() {
  local repo="$1"
  if repo_exists "$repo"; then
    echo "Repo '$repo' exists."
  else
    if [[ "$CREATE_LL_REPO" == "true" ]]; then
      echo "Creating repo '$repo'..."
      aws_ca create-repository --domain "$CA_DOMAIN" --repository "$repo" \
        --description "Auto-created for long-lived branch"
    else
      echo "ERROR: Repo '$repo' not found and CREATE_LL_REPO=false" >&2
      exit 1
    fi
  fi
}

# Sanitize branch name into a valid CodeArtifact repository name
sanitize_repo_name() {
  # Allowed: [A-Za-z0-9._-]
  # - replace slashes and spaces with dashes
  # - collapse repeats, trim edges
  local s="$1"
  s="$(printf '%s' "$s" | tr '/[:space:]' '-' | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-{2,}/-/g; s/^-+//; s/-+$//')"
  # avoid empty or leading dot/hyphen names
  if [ -z "$s" ] || printf '%s' "$s" | grep -Eq '^[.-]'; then
    s="ll-repo"
  fi
  printf '%s' "$s"
}

normalize_url() { case "$1" in */) printf '%s' "$1";; *) printf '%s/' "$1";; esac; }

write_properties() {
  local resolve_ep="$1" deploy_ep="$2"
  : > file.properties
  printf 'pluginRepositoryUrl=%s\n'        "$deploy_ep"   >> file.properties
  printf 'mavenFeatureRepositoryUrl=%s\n'  "$deploy_ep"   >> file.properties
  printf 'resolveRepositoryUrl=%s\n'       "$resolve_ep"  >> file.properties
  printf 'isLongLived=%s\n'                "$IS_LL"       >> file.properties
  echo "Wrote file.properties:"
  cat file.properties
}

write_settings_with_mirror() {
  # Writes settings-ca.xml with:
  #  - mirror forcing all resolution through CodeArtifact
  #  - server credentials that read the short-lived token from env
  local resolve_ep="$1"
  # Hide token during retrieval even if script is run with `bash -x`
  local xtrace_on=0
  [[ $- == *x* ]] && xtrace_on=1 && set +x
  export CODEARTIFACT_AUTH_TOKEN="$(
    aws_ca get-authorization-token \
      --domain "$CA_DOMAIN" \
      --query authorizationToken \
      --output text
  )"
  (( xtrace_on )) && set -x
  cat > settings-ca.xml <<XML
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <mirrors>
    <mirror>
      <id>codeartifact-all</id>
      <mirrorOf>*</mirrorOf>
      <url>${resolve_ep}</url>
    </mirror>
  </mirrors>
  <servers>
    <server>
      <id>codeartifact</id>
      <username>aws</username>
      <password>\${env.CODEARTIFACT_AUTH_TOKEN}</password>
    </server>
  </servers>
</settings>
XML
  echo "Wrote settings-ca.xml"
}

# --- Branch detection helper (Bamboo env vars first, then fallbacks) ---
detect_branch() {
  # Prefer Bamboo-provided vars from the primary repo
  for var in \
    bamboo_planRepository_branch \
    bamboo_planRepository_1_branch \
    BAMBOO_PLANREPOSITORY_BRANCH \
    BAMBOO_PLANREPOSITORY_1_BRANCH \
    PLAN_REPO_BRANCH \
    PARENT_REPO_BRANCH
  do
    val="${!var:-}"
    [ -n "$val" ] && { printf '%s' "$val"; return; }
  done
  # Fallback: try parent repo dir if provided, else current repo
  if [ -n "${PARENT_REPO_DIR:-}" ] && [ -d "$PARENT_REPO_DIR/.git" ]; then
    (cd "$PARENT_REPO_DIR" && git rev-parse --abbrev-ref HEAD) 2>/dev/null && return
  fi
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown
}

###############################################
# Branch detection and repo selection
###############################################
BranchName="$(detect_branch | tr -d '\n')"
echo "BranchName=${BranchName}"

to_bool() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in 1|true|yes|y) echo true;; *) echo false;; esac; }

IS_LL=false
if [ -n "${FORCE_LONG_LIVED:-}" ]; then
  IS_LL="$(to_bool "$FORCE_LONG_LIVED")"
else
  if printf '%s' "$BranchName" | grep -Eiq "$LONG_LIVED_REGEX"; then
    IS_LL=true
  elif printf '%s' "$BranchName" | grep -Eiq "^${LONG_LIVED_PREFIX}"; then
    # legacy compatibility (branches starting with "LL")
    IS_LL=true
  fi
fi

ResolveRepo="$DEFAULT_VIRTUAL_REPO"
if [ "$IS_LL" = true ]; then
  echo "Long-lived branch detected."
  DeployRepo="$(sanitize_repo_name "$BranchName")"
  ensure_repo_exists "$DeployRepo"
else
  echo "Not a long-lived branch."
  DeployRepo="$DEFAULT_VIRTUAL_REPO"
fi

ResolveEndpoint="$(normalize_url "$(endpoint_for_repo "$ResolveRepo")")"
DeployEndpoint="$(normalize_url "$(endpoint_for_repo "$DeployRepo")")"

if [[ -z "${ResolveEndpoint:-}" || -z "${DeployEndpoint:-}" ]]; then
  echo "ERROR: Failed to obtain repository endpoints from CodeArtifact." >&2
  exit 1
fi

echo "ResolveRepo=$ResolveRepo"
echo "DeployRepo=$DeployRepo"
echo "ResolveEndpoint=$ResolveEndpoint"
echo "DeployEndpoint=$DeployEndpoint"

write_properties "$ResolveEndpoint" "$DeployEndpoint"

if [[ "$WRITE_MAVEN_SETTINGS" == "1" ]]; then
  write_settings_with_mirror "$ResolveEndpoint"
fi

echo "Done."

###############################################
# Helper: gate deploys by isLongLived
###############################################
deploy_if_long_lived() {
  local props="file.properties"
  local flag

  if [[ ! -f $props ]]; then
    echo "ERROR: $props not found; cannot determine isLongLived" >&2
    return 1
  fi

  flag="$(awk -F= '/^isLongLived[[:space:]]*=/{print $2}' "$props" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g')"
  case "${flag:-false}" in
    true|yes|1)
      echo "isLongLived=true — proceeding to deploy."
      return 0
      ;;
    *)
      echo "isLongLived=false — skipping deploy."
      return 1
      ;;
  esac
}