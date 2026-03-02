#!/usr/bin/env bash
set -euo pipefail

# ======= REQUIRED CONFIG =======
: "${REGION:?Set REGION (e.g. us-east-1)}"
: "${DOMAIN:?Set DOMAIN (e.g. cnxsartifact)}"
: "${OWNER:?Set OWNER AWS account id (e.g. 339713019047)}"

# Default repo if mapping doesn't match
: "${REPO_DEFAULT:=conexus-dependencies}"

# Routing targets
: "${REPO_PLUGIN:=conexus-plugin-repository}"
: "${REPO_DEPENDENCIES:=conexus-dependencies}"

# Internal groupId prefixes (space-separated)
: "${INTERNAL_GROUP_PREFIXES:=com.cnxs gov.gsa.cnxs}"

# Upstream repos to check for already-available packages (space-separated)
: "${UPSTREAM_REPOS:=conexus-dependencies feature-ll-postgres ll-postgres}"

# Optional mapping for multi-root zip layout (space-separated key=value, e.g. "rootA=repo1 rootB=repo2")
: "${REPO_MAP:=}"

# Optional: DRY_RUN=1 to only print actions (no uploads)
: "${DRY_RUN:=0}"

# Optional: MAX_JOBS>1 enables simple parallelism (only after validation)
: "${MAX_JOBS:=1}"

# Optional: VERBOSE=1 prints extra tracing
: "${VERBOSE:=0}"

# ======= ARGS =======
if [[ $# -ne 1 ]]; then
  echo "Usage: REGION=... DOMAIN=... OWNER=... [DRY_RUN=1] $0 /path/to/repository.zip"
  exit 2
fi

ZIPFILE="$1"
if [[ ! -f "$ZIPFILE" ]]; then
  echo "Zip not found: $ZIPFILE"
  exit 2
fi

# ======= TOOLING CHECKS =======
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 3; }; }
need aws; need unzip; need mvn; need find; need awk; need basename; need dirname; need grep; need sed; need tr; need mktemp; need sort; need cp; need rm

# ======= STAGING / UNZIP =======
ZIP_BASENAME="$(basename "$ZIPFILE")"
STAGE_DIR="$HOME/staging/${ZIP_BASENAME%.zip}"
mkdir -p "$STAGE_DIR"

echo ">> Unzipping to: $STAGE_DIR"
unzip -q -o "$ZIPFILE" -d "$STAGE_DIR"

# Maven root
if [[ -d "$STAGE_DIR/repository" ]]; then
  ROOTS=("$STAGE_DIR/repository")
else
  ROOT="$(find "$STAGE_DIR" -maxdepth 3 -type d -name repository | head -n1 || true)"
  [[ -n "${ROOT:-}" && -d "$ROOT" ]] || {
    echo "!! Expected Maven root not found. Looked for: $STAGE_DIR/repository (and fallback search)."
    echo "   Inspect: tree -L 3 $STAGE_DIR"
    exit 4
  }
  ROOTS=("$ROOT")
fi

echo ">> Using Maven root(s):"
for r in "${ROOTS[@]}"; do echo "   - $r"; done

# ======= AUTH + SETTINGS =======
TOKEN="$(aws codeartifact get-authorization-token \
  --domain "$DOMAIN" --domain-owner "$OWNER" --region "$REGION" \
  --query authorizationToken --output text)"

SETTINGS="$(mktemp)"
cat > "$SETTINGS" <<EOF
<settings>
  <servers>
    <server>
      <id>codeartifact</id>
      <username>aws</username>
      <password>${TOKEN}</password>
    </server>
  </servers>
</settings>
EOF
cleanup() { rm -f "$SETTINGS"; }
trap cleanup EXIT

# ======= Endpoint cache =======
declare -A ENDPOINT_CACHE
endpoint_for_repo() {
  local repo="$1"
  if [[ -n "${ENDPOINT_CACHE[$repo]:-}" ]]; then
    echo "${ENDPOINT_CACHE[$repo]}"
    return 0
  fi
  local ep
  ep="$(aws codeartifact get-repository-endpoint \
    --domain "$DOMAIN" --domain-owner "$OWNER" --repository "$repo" \
    --format maven --region "$REGION" --query repositoryEndpoint --output text)"
  ENDPOINT_CACHE["$repo"]="$ep"
  echo "$ep"
}

# ======= Existence & asset checks =======
exists_in_repo() {
  local repo="$1" group="$2" artifact="$3" version="$4"
  aws codeartifact describe-package-version \
    --region "$REGION" \
    --domain "$DOMAIN" --domain-owner "$OWNER" \
    --repository "$repo" \
    --format maven \
    --namespace "$group" \
    --package "$artifact" \
    --package-version "$version" >/dev/null 2>&1
}

# Cache assets to avoid re-listing repeatedly
declare -A ASSET_CACHE
list_assets_cached() {
  local repo="$1" group="$2" artifact="$3" version="$4"
  local key="${repo}|${group}|${artifact}|${version}"
  if [[ -n "${ASSET_CACHE[$key]:-}" ]]; then
    printf '%s\n' "${ASSET_CACHE[$key]}"
    return 0
  fi

  if ! exists_in_repo "$repo" "$group" "$artifact" "$version"; then
    ASSET_CACHE["$key"]=$'\n'
    return 0
  fi

  local names
  names="$(aws codeartifact list-package-version-assets \
    --region "$REGION" \
    --domain "$DOMAIN" --domain-owner "$OWNER" \
    --repository "$repo" \
    --format maven \
    --namespace "$group" \
    --package "$artifact" \
    --package-version "$version" \
    --query 'assets[].name' --output text 2>/dev/null | tr '\t' '\n' || true)"

  ASSET_CACHE["$key"]="$names"
  printf '%s\n' "$names"
}

repo_has_asset_regex() {
  local repo="$1" group="$2" artifact="$3" version="$4" regex="$5"
  local assets
  assets="$(list_assets_cached "$repo" "$group" "$artifact" "$version")"
  printf '%s\n' "$assets" | grep -Eq "$regex"
}

# Decide what this version MUST have (based on what is present locally)
# IMPORTANT: use explicit if statements so set -e never kills the script on grep non-match
determine_required_suffixes() {
  local files="$1"
  echo "pom"

  if printf '%s\n' "$files" | grep -Eq '\.bundle$'; then
    echo "jar"
  elif printf '%s\n' "$files" | grep -Eq '\.jar$'; then
    echo "jar"
  fi

  if printf '%s\n' "$files" | grep -Eq '\.war$'; then echo "war"; fi
  if printf '%s\n' "$files" | grep -Eq '\.ear$'; then echo "ear"; fi
  if printf '%s\n' "$files" | grep -Eq '\.zip$'; then echo "zip"; fi
  if printf '%s\n' "$files" | grep -Eq '(\.tgz$|\.tar\.gz$)'; then echo "tar.gz"; fi
}

# Upstream skip ONLY if upstream has the required assets (not just the version)
exists_complete_in_any_upstream() {
  local group="$1" artifact="$2" version="$3" req_suffixes="$4"
  local upstream
  for upstream in $UPSTREAM_REPOS; do
    if ! exists_in_repo "$upstream" "$group" "$artifact" "$version"; then
      continue
    fi

    local ok=1 suf
    while read -r suf; do
      [[ -z "$suf" ]] && continue
      case "$suf" in
        pom)
          repo_has_asset_regex "$upstream" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.pom$" || { ok=0; break; }
          ;;
        jar)
          repo_has_asset_regex "$upstream" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.jar$" || { ok=0; break; }
          ;;
        war|ear|zip)
          repo_has_asset_regex "$upstream" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.${suf}$" || { ok=0; break; }
          ;;
        tar.gz)
          repo_has_asset_regex "$upstream" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.tar\.gz$" || { ok=0; break; }
          ;;
      esac
    done <<< "$req_suffixes"

    if [[ "$ok" -eq 1 ]]; then
      echo "$upstream"
      return 0
    fi
  done
  return 1
}

# ======= Repo label helpers =======
repo_for_root_label() {
  local label="$1"
  local kv k v
  for kv in $REPO_MAP; do
    k="${kv%%=*}"
    v="${kv#*=}"
    if [[ "$k" == "$label" ]]; then
      echo "$v"
      return 0
    fi
  done
  echo "$REPO_DEFAULT"
}

root_label_for_path() {
  local root="$1"
  local path="$2"

  # If no REPO_MAP is provided, do NOT try to infer labels from folder names.
  if [[ -z "${REPO_MAP// }" ]]; then
    echo ""
    return 0
  fi

  local rel="${path#$root/}"
  local first="${rel%%/*}"
  case "$first" in
    com|org|net|io|javax|jakarta|edu|gov|mil) echo ""; return 0 ;;
  esac
  echo "$first"
}

# ======= File/packaging helpers =======
infer_packaging_from_filename() {
  local file="$1"
  case "$file" in
    *.pom) echo "pom" ;;
    *.jar) echo "jar" ;;
    *.war) echo "war" ;;
    *.ear) echo "ear" ;;
    *.zip) echo "zip" ;;
    *.tgz) echo "tar.gz" ;;
    *.tar.gz) echo "tar.gz" ;;
    *.bundle) echo "jar" ;; # treat bundle content as jar bytes
    *) echo "" ;;
  esac
}

gather_artifacts_for_version_dir() {
  local version_dir="$1" artifact="$2" version="$3"
  find "$version_dir" -maxdepth 1 -type f \
    \( -name "${artifact}-${version}*.jar" \
       -o -name "${artifact}-${version}*.war" \
       -o -name "${artifact}-${version}*.ear" \
       -o -name "${artifact}-${version}*.zip" \
       -o -name "${artifact}-${version}*.tgz" \
       -o -name "${artifact}-${version}*.tar.gz" \
       -o -name "${artifact}-${version}*.bundle" \
       -o -name "${artifact}-${version}.pom" \
    \) \
    ! -name "*.sha1" ! -name "*.md5" ! -name "*.sha256" ! -name "*.sha512" \
    ! -name "*.lastUpdated" ! -name "_remote.repositories" ! -name "maven-metadata-local.xml" \
    -print | sort
}

deploy_file() {
  local repo="$1" endpoint="$2" file="$3" pom="$4" classifier="${5:-}" packaging="${6:-}"
  local extra=()
  [[ -n "$classifier" ]] && extra+=("-Dclassifier=$classifier")
  [[ -n "$packaging"  ]] && extra+=("-Dpackaging=$packaging")

  if [[ "$DRY_RUN" = "1" ]]; then
    echo "DRY-RUN deploy -> repo=$repo file=$(basename "$file") packaging=${packaging:-auto} classifier=${classifier:-none} pom=$(basename "$pom")"
    return 0
  fi

  local out
  out="$(mvn -q -s "$SETTINGS" deploy:deploy-file \
    -Durl="$endpoint" -DrepositoryId=codeartifact \
    -DpomFile="$pom" -Dfile="$file" "${extra[@]}" 2>&1)" || {
      if echo "$out" | grep -q "status: 409 Conflict"; then
        echo "-- SKIP (409 already exists) $(basename "$file")"
        return 2
      fi
      echo "$out"
      return 1
    }
  return 0
}

# ======= MAIN LOOP =======
published=0
skipped_local=0
skipped_upstream=0
skipped_409=0
errors=0

process_pom() {
  local ROOT="$1"
  local POM="$2"

  case "$POM" in
    *.lastUpdated|*.sha1|*/_remote.repositories|*/maven-metadata-local.xml) return 0 ;;
  esac

  local version_dir artifact_dir version artifact
  version_dir="$(dirname "$POM")"
  artifact_dir="$(dirname "$version_dir")"
  version="$(basename "$version_dir")"
  artifact="$(basename "$artifact_dir")"

  local group_path label repo group
  group_path="${artifact_dir#$ROOT/}"
  group_path="${group_path%/$artifact}"

  label="$(root_label_for_path "$ROOT" "$POM")"
  repo="$REPO_DEFAULT"
  if [[ -n "$label" ]]; then
    repo="$(repo_for_root_label "$label")"
    group_path="${group_path#${label}/}"
  fi
  group="${group_path//\//.}"

  local is_internal=0 pfx
  for pfx in $INTERNAL_GROUP_PREFIXES; do
    if [[ "$group" == "$pfx"* ]]; then is_internal=1; break; fi
  done

  if [[ $is_internal -eq 1 ]]; then
    repo="$REPO_PLUGIN"
  else
    repo="$REPO_DEPENDENCIES"
  fi

  local canonical_pom="$version_dir/$artifact-$version.pom"
  [[ -f "$canonical_pom" ]] || canonical_pom="$POM"

  mapfile -t files < <(gather_artifacts_for_version_dir "$version_dir" "$artifact" "$version")
  if [[ "${#files[@]}" -eq 0 ]]; then
    return 0
  fi

  local filelist req_suffixes
  filelist="$(printf '%s\n' "${files[@]}")"
  req_suffixes="$(determine_required_suffixes "$filelist")"

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "DEBUG: $group:$artifact:$version -> repo=$repo"
    echo "DEBUG: required:"
    printf '  - %s\n' $req_suffixes
  fi

  # Non-internal upstream skip ONLY if upstream is COMPLETE
  if [[ $is_internal -eq 0 ]]; then
    if up="$(exists_complete_in_any_upstream "$group" "$artifact" "$version" "$req_suffixes")"; then
      echo "-- SKIP (exists upstream COMPLETE in $up) $group:$artifact:$version"
      ((skipped_upstream++)) || true
      return 0
    fi
  fi

  # Target skip ONLY if target is COMPLETE
  if exists_in_repo "$repo" "$group" "$artifact" "$version"; then
    local ok=1 suf
    while read -r suf; do
      [[ -z "$suf" ]] && continue
      case "$suf" in
        pom) repo_has_asset_regex "$repo" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.pom$" || ok=0 ;;
        jar) repo_has_asset_regex "$repo" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.jar$" || ok=0 ;;
        war|ear|zip) repo_has_asset_regex "$repo" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.${suf}$" || ok=0 ;;
        tar.gz) repo_has_asset_regex "$repo" "$group" "$artifact" "$version" "^${artifact}-${version}.*\.tar\.gz$" || ok=0 ;;
      esac
      [[ "$ok" -eq 1 ]] || break
    done <<< "$req_suffixes"

    if [[ "$ok" -eq 1 ]]; then
      echo "-- SKIP (exists in target COMPLETE) $group:$artifact:$version (repo=$repo)"
      ((skipped_local++)) || true
      return 0
    fi

    echo "-- NOTE target has version but missing required assets; will publish missing: $group:$artifact:$version (repo=$repo)"
  fi

  local endpoint
  endpoint="$(endpoint_for_repo "$repo")"

  echo ">> PUBLISH $group:$artifact:$version repo=$repo (files=${#files[@]})"

  local f rc packaging classifier
  for f in "${files[@]}"; do
    packaging="$(infer_packaging_from_filename "$f")"
    classifier=""

    case "$(basename "$f")" in
      *-sources.jar) classifier="sources"; packaging="jar" ;;
      *-javadoc.jar) classifier="javadoc"; packaging="jar" ;;
    esac

    # handle .bundle by publishing a .jar only when needed
    if [[ "$classifier" == "" && "$f" == *.bundle ]]; then
      if repo_has_asset_regex "$repo" "$group" "$artifact" "$version" "^${artifact}-${version}\.jar$"; then
        echo "-- NOTE jar already present in repo=$repo for $group:$artifact:$version; skipping bundle->jar"
        continue
      fi

      echo "-- BUNDLE-ONLY detected; publishing ${artifact}-${version}.jar from $(basename "$f")"

      local tmpdir tmpjar
      tmpdir="$(mktemp -d)"
      tmpjar="${tmpdir}/${artifact}-${version}.jar"
      cp -f "$f" "$tmpjar"

      rc=0
      deploy_file "$repo" "$endpoint" "$tmpjar" "$canonical_pom" "" "jar" || rc=$?

      rm -rf "$tmpdir"

      if [[ $rc -eq 2 ]]; then
        ((skipped_409++)) || true
      elif [[ $rc -ne 0 ]]; then
        ((errors++)) || true
        echo "!! ERROR deploying bundle-as-jar for $group:$artifact:$version"
      fi

      unset 'ASSET_CACHE["'"${repo}|${group}|${artifact}|${version}"'"]' || true
      continue
    fi

    rc=0
    deploy_file "$repo" "$endpoint" "$f" "$canonical_pom" "$classifier" "$packaging" || rc=$?
    if [[ $rc -eq 2 ]]; then
      ((skipped_409++)) || true
    elif [[ $rc -ne 0 ]]; then
      ((errors++)) || true
      echo "!! ERROR deploying $(basename "$f") for $group:$artifact:$version"
    fi

    unset 'ASSET_CACHE["'"${repo}|${group}|${artifact}|${version}"'"]' || true
  done

  ((published++)) || true
}

export -f process_pom
export REGION DOMAIN OWNER REPO_DEFAULT REPO_PLUGIN REPO_DEPENDENCIES INTERNAL_GROUP_PREFIXES UPSTREAM_REPOS DRY_RUN VERBOSE
export SETTINGS REPO_MAP
export -f endpoint_for_repo exists_in_repo root_label_for_path repo_for_root_label
export -f infer_packaging_from_filename gather_artifacts_for_version_dir deploy_file
export -f list_assets_cached repo_has_asset_regex determine_required_suffixes exists_complete_in_any_upstream

for ROOT in "${ROOTS[@]}"; do
  echo
  echo ">> Scanning for POMs under: $ROOT"
  mapfile -d '' POMS < <(find "$ROOT" -type f -name "*.pom" -print0)

  if [[ "${#POMS[@]}" -eq 0 ]]; then
    echo "!! No *.pom files found under $ROOT"
    continue
  fi

  if [[ "$MAX_JOBS" -gt 1 ]]; then
    printf '%s\0' "${POMS[@]}" | xargs -0 -n 1 -P "$MAX_JOBS" bash -lc 'process_pom "$0" "$1"' "$ROOT"
  else
    for POM in "${POMS[@]}"; do
      process_pom "$ROOT" "$POM"
    done
  fi
done

echo
echo "===== SUMMARY ====="
echo "Published (coords processed): $published"
echo "Skipped (exists in target COMPLETE):  $skipped_local"
echo "Skipped (exists upstream COMPLETE):   $skipped_upstream"
echo "Skipped (409 conflict):              $skipped_409"
echo "Errors:                              $errors"
[[ "$DRY_RUN" = "1" ]] && echo "(Dry run only; nothing actually uploaded.)"