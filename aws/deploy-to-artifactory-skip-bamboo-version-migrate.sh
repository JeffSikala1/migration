#!/usr/bin/env bash
# deploy-to-artifactory-skip-bamboo-version-migrate.sh
# Migrate legacy Artifactory deploy script to AWS CodeArtifact.
# Deploys for LL parent branches and develop; skips LL child and feature branches.

set -Eeuo pipefail

###############################################
# Config (override via env)
###############################################
CA_REGION="${CA_REGION:-us-east-1}"
CA_DOMAIN="${CA_DOMAIN:-cnxsartifact}"
CA_ACCOUNT="${CA_ACCOUNT:-339713019047}"

LONG_LIVED_PREFIX="${LONG_LIVED_PREFIX:-ll-}"                # e.g., ll-foo or ll-foo+child
DEFAULT_VIRTUAL_REPO="${DEFAULT_VIRTUAL_REPO:-conexus-plugin-repository}"
LL_PLUGIN_REPO_NAME="${LL_PLUGIN_REPO_NAME:-conexus-plugin-repository}"
CREATE_LL_REPO="${CREATE_LL_REPO:-true}"

WRITE_MAVEN_SETTINGS="${WRITE_MAVEN_SETTINGS:-1}"            # write settings-ca.xml with mirror+token
NO_DEPLOY="${NO_DEPLOY:-0}"                                   # set to 1 on dev boxes w/out a POM
POM_PATH="${POM_PATH:-}"                                      # optional explicit pom.xml path

###############################################
# Helpers
###############################################
aws_ca() {
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

write_properties() {
  local branch_name="$1" child_name="$2" plugin_ep="$3" feature_ep="$4" resolve_ep="$5"
  : > file.properties
  printf 'BranchName=%s\n'                 "$branch_name"   >> file.properties
  [[ -n "${child_name}" ]] && printf 'ChildBranchName=%s\n' "$child_name" >> file.properties
  printf 'pluginRepositoryUrl=%s\n'        "$plugin_ep"     >> file.properties
  printf 'mavenFeatureRepositoryUrl=%s\n'  "$feature_ep"    >> file.properties
  printf 'resolveRepositoryUrl=%s\n'       "$resolve_ep"    >> file.properties
  echo "Wrote file.properties:"
  cat file.properties
}

write_settings_with_mirror() {
  # Mirror id MUST match server id so Maven uses same credentials
  local resolve_ep="$1"
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
      <id>codeartifact</id>
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

resolve_pom_path() {
  if [[ -n "$POM_PATH" ]]; then
    [[ -f "$POM_PATH" ]] || { echo "ERROR: POM_PATH '$POM_PATH' not found." >&2; exit 3; }
    echo "$POM_PATH"; return
  fi
  if [[ -f "pom.xml" ]]; then echo "pom.xml"; return; fi
  mapfile -t found < <(find . -name pom.xml -not -path "*/target/*" | sort)
  (( ${#found[@]} )) || { echo "ERROR: No pom.xml found in $(pwd). Set POM_PATH or run from a project directory." >&2; exit 3; }
  local shortest="${found[0]}"
  for p in "${found[@]}"; do [[ ${#p} -lt ${#shortest} ]] && shortest="$p"; done
  echo "$shortest"
}

###############################################
# Branch detection
###############################################
BranchRef="$(git rev-parse --abbrev-ref HEAD | tr -d '\n')"
BranchName="${BranchRef##*/}"
echo "BranchRef=${BranchRef}"
echo "BranchName=${BranchName}"

###############################################
# Resolve through virtual-like aggregator
###############################################
ResolveRepo="$DEFAULT_VIRTUAL_REPO"
ResolveEndpoint="$(endpoint_for_repo "$ResolveRepo")"

# Always generate settings so dev boxes can run smoke tests
[[ "$WRITE_MAVEN_SETTINGS" == "1" ]] && write_settings_with_mirror "$ResolveEndpoint"

###############################################
# Long-lived handling
###############################################
if [[ "${BranchName:0:${#LONG_LIVED_PREFIX}}" == "$LONG_LIVED_PREFIX" ]]; then
  echo "This is a long-lived branch."
  ParentBranchName="$(printf '%s' "$BranchName" | cut -d'+' -f1)"
  ChildBranchName="$(printf '%s' "$BranchName" | cut -d'+' -f2 -s || true)"

  PluginRepo="$LL_PLUGIN_REPO_NAME"
  PluginEndpoint="$(endpoint_for_repo "$PluginRepo")"

  ensure_repo_exists "$ParentBranchName"
  FeatureEndpoint="$(endpoint_for_repo "$ParentBranchName")"

  write_properties "$ParentBranchName" "${ChildBranchName:-}" "$PluginEndpoint" "$FeatureEndpoint" "$ResolveEndpoint"

  if [[ -z "${ChildBranchName:-}" ]]; then
    echo "Parent long-lived branch → deploying."
    if (( NO_DEPLOY )); then
      echo "NO_DEPLOY=1 — skipping mvn deploy"
    else
      POM_TO_USE="$(resolve_pom_path)"
      echo "Using POM: $POM_TO_USE"
      mvn -B -U -s settings-ca.xml -f "$POM_TO_USE" deploy -DskipTests=true \
        -Dbamboo.inject.BranchName="$ParentBranchName" \
        -Dbamboo.inject.mavenFeatureRepositoryUrl="$FeatureEndpoint" \
        -Dbamboo.inject.pluginRepositoryUrl="$PluginEndpoint" \
        -DaltDeploymentRepository=codeartifact::"$FeatureEndpoint"
    fi
  else
    echo "Child long-lived branch → not deploying."
  fi

###############################################
# Non long-lived: develop and others
###############################################
else
  echo "Not a long-lived branch."
  PluginRepo="$DEFAULT_VIRTUAL_REPO"
  PluginEndpoint="$(endpoint_for_repo "$PluginRepo")"
  FeatureEndpoint="$PluginEndpoint"

  write_properties "$BranchName" "" "$PluginEndpoint" "$FeatureEndpoint" "$ResolveEndpoint"

  if [[ "$BranchName" == "develop" ]]; then
    echo "Development branch → deploying."
    if (( NO_DEPLOY )); then
      echo "NO_DEPLOY=1 — skipping mvn deploy"
    else
      POM_TO_USE="$(resolve_pom_path)"
      echo "Using POM: $POM_TO_USE"
      mvn -B -U -s settings-ca.xml -f "$POM_TO_USE" deploy -DskipTests=true \
        -Dbamboo.inject.BranchName="$BranchName" \
        -Dbamboo.inject.mavenFeatureRepositoryUrl="$FeatureEndpoint" \
        -Dbamboo.inject.pluginRepositoryUrl="$PluginEndpoint" \
        -DaltDeploymentRepository=codeartifact::"$FeatureEndpoint"
    fi
  else
    echo "Feature/other branch → not deploying."
  fi
fi

echo
echo "contents of file.properties"
echo
cat file.properties