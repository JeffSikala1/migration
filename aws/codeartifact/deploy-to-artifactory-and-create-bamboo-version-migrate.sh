#!/usr/bin/env bash
# deploy-to-artifactory-and-create-bamboo-version-migrate.sh
# CodeArtifact deploy with long-lived branch handling and Bamboo version injection.

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
WRITE_MAVEN_SETTINGS="${WRITE_MAVEN_SETTINGS:-1}"
NO_DEPLOY="${NO_DEPLOY:-0}"                                   # set to 1 on dev boxes w/out a POM

# Optional: force which pom.xml to use (absolute or relative path)
POM_PATH="${POM_PATH:-}"

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
  # Write a settings file that can resolve from CodeArtifact (resolve repo)
  # and also fall back to Red Hat GA and Maven Central for productized coords.
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
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">

  <servers>
    <!-- Used by repositories below -->
    <server>
      <id>ca-resolve</id>
      <username>aws</username>
      <password>\${env.CODEARTIFACT_AUTH_TOKEN}</password>
    </server>
    <!-- Used by -DaltDeploymentRepository=codeartifact::default::<FeatureEndpoint> -->
    <server>
      <id>codeartifact</id>
      <username>aws</username>
      <password>\${env.CODEARTIFACT_AUTH_TOKEN}</password>
    </server>
  </servers>

  <profiles>
    <profile>
      <id>codeartifact</id>

      <repositories>
        <!-- Your CodeArtifact resolve repo -->
        <repository>
          <id>ca-resolve</id>
          <url>${resolve_ep}</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </repository>

        <!-- Fallbacks for productized coords (e.g., *.redhat-0000X) -->
        <repository>
          <id>rh-ga</id>
          <url>https://maven.repository.redhat.com/ga/</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </repository>

        <!-- Optional last resort -->
        <repository>
          <id>central</id>
          <url>https://repo1.maven.org/maven2/</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </repository>
      </repositories>

      <pluginRepositories>
        <pluginRepository>
          <id>ca-resolve</id>
          <url>${resolve_ep}</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>true</enabled></snapshots>
        </pluginRepository>
        <pluginRepository>
          <id>rh-ga</id>
          <url>https://maven.repository.redhat.com/ga/</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </pluginRepository>
        <pluginRepository>
          <id>central</id>
          <url>https://repo1.maven.org/maven2/</url>
          <releases><enabled>true</enabled></releases>
          <snapshots><enabled>false</enabled></snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>

    <!-- Separate deps profile to ensure external fallbacks are always available -->
    <profile>
      <id>deps</id>
      <repositories>
        <repository>
          <id>rh-ga</id>
          <url>https://maven.repository.redhat.com/ga/</url>
        </repository>
        <repository>
          <id>central</id>
          <url>https://repo1.maven.org/maven2/</url>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>rh-ga</id>
          <url>https://maven.repository.redhat.com/ga/</url>
        </pluginRepository>
        <pluginRepository>
          <id>central</id>
          <url>https://repo1.maven.org/maven2/</url>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>

  <activeProfiles>
    <activeProfile>codeartifact</activeProfile>
    <activeProfile>deps</activeProfile>
  </activeProfiles>
</settings>
XML

  echo "Wrote settings-ca.xml (profiles: codeartifact + deps; includes ca-resolve + rh-ga + central; deploy creds id=codeartifact)"
}

# Highest published version for group/artifact in repo; optional 4th arg filters by prefix/exact (mavenVersion).
get_latest_version_in_repo() {
  local repo="$1" group="$2" artifact="$3" maven_base="${4:-}"

  mapfile -t versions < <(
    aws_ca list-package-versions \
      --domain "$CA_DOMAIN" \
      --repository "$repo" \
      --format maven \
      --namespace "$group" \
      --package "$artifact" \
      --query 'versions[?status==`Published`].version' \
      --output text | tr '\t' '\n' | sed '/^$/d'
  ) || true

  [[ ${#versions[@]} -eq 0 ]] && return 1

  local filtered=()
  if [[ -n "$maven_base" ]]; then
    if [[ "$maven_base" == *"*"* ]]; then
      local prefix="${maven_base%%\**}"
      for v in "${versions[@]}"; do [[ "$v" == "$prefix"* ]] && filtered+=("$v"); done
    else
      for v in "${versions[@]}"; do [[ "$v" == "$maven_base" ]] && { printf '%s\n' "$v"; return 0; }; done
      for v in "${versions[@]}"; do [[ "$v" == "$maven_base"* ]] && filtered+=("$v"); done
    fi
  fi

  [[ ${#filtered[@]} -eq 0 ]] && filtered=("${versions[@]}")
  printf '%s\n' "${filtered[@]}" | sort -V | tail -n1
}

write_latest_version_property() {
  local repo="$1"
  if [[ -n "${buildVersionQueryArtifact:-}" && -n "${buildVersionQueryGroup:-}" ]]; then
    local lv
    lv="$(get_latest_version_in_repo "$repo" "$buildVersionQueryGroup" "$buildVersionQueryArtifact" "${mavenVersion:-}")" || true
    if [[ -n "${lv:-}" ]]; then
      printf 'latestVersion=%s\n' "$lv" >> file.properties
      echo "latestVersion resolved in repo '$repo' → $lv"
    else
      echo "latestVersion could not be resolved in repo '$repo' (no matches)."
    fi
  else
    echo "Skipping latestVersion: buildVersionQueryArtifact/buildVersionQueryGroup not provided."
  fi
}

resolve_pom_path() {
  if [[ -n "$POM_PATH" ]]; then
    [[ -f "$POM_PATH" ]] || { echo "ERROR: POM_PATH '$POM_PATH' not found." >&2; exit 3; }
    echo "$POM_PATH"
    return
  fi
  if [[ -f "pom.xml" ]]; then
    echo "pom.xml"
    return
  fi
  mapfile -t found < <(find . -name pom.xml -not -path "*/target/*" | sort)
  if (( ${#found[@]} == 0 )); then
    echo "ERROR: No pom.xml found in $(pwd). Set POM_PATH or run from a project directory." >&2
    exit 3
  fi
  local shortest="${found[0]}"
  for p in "${found[@]}"; do
    [[ ${#p} -lt ${#shortest} ]] && shortest="$p"
  done
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

# Always generate settings (so dev boxes can run smoke tests)
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
        -DaltDeploymentRepository=codeartifact::default::"$FeatureEndpoint"
    fi
    write_latest_version_property "$ParentBranchName"
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

  if (( NO_DEPLOY )); then
    echo "NO_DEPLOY=1 — skipping mvn deploy"
  else
    POM_TO_USE="$(resolve_pom_path)"
    echo "Using POM: $POM_TO_USE"
    if [[ "$BranchName" == "develop" ]]; then
      echo "Development branch → deploying."
      mvn -B -U -s settings-ca.xml -f "$POM_TO_USE" deploy -DskipTests=true \
        -Dbamboo.inject.BranchName="$BranchName" \
        -Dbamboo.inject.mavenFeatureRepositoryUrl="$FeatureEndpoint" \
        -Dbamboo.inject.pluginRepositoryUrl="$PluginEndpoint" \
        -DaltDeploymentRepository=codeartifact::default::"$FeatureEndpoint"
      write_latest_version_property "conexus-snapshot-local"
    else
      echo "Feature/other branch → deploying."
      mvn -B -U -s settings-ca.xml -f "$POM_TO_USE" deploy -DskipTests=true \
        -Dbamboo.inject.BranchName="$BranchName" \
        -Dbamboo.inject.mavenFeatureRepositoryUrl="$FeatureEndpoint" \
        -Dbamboo.inject.pluginRepositoryUrl="$PluginEndpoint" \
        -DaltDeploymentRepository=codeartifact::default::"$FeatureEndpoint"
      write_latest_version_property "conexus-snapshot-local"
    fi
  fi
fi

echo
echo "contents of file.properties"
echo
cat file.properties