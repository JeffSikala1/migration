#!/usr/bin/env bash
set -euo pipefail

# ======= REQUIRED CONFIG (export before running or edit here) =======
: "${REGION:?Set REGION (e.g. us-east-1)}"
: "${DOMAIN:?Set DOMAIN (e.g. cnxsartifact)}"
: "${OWNER:?Set OWNER AWS account id (e.g. 339713019047)}"
: "${REPO_SRC:?Set REPO_SRC (e.g. conexus-dependencies)}"
# Optional mirror/copy destination (e.g. conexus-plugin-repository). Leave unset to disable copy step.
: "${REPO_DST:=}"

# Optional: DRY_RUN=1 to only print actions (no uploads)
: "${DRY_RUN:=0}"

# ======= ARGS =======
if [[ $# -ne 1 ]]; then
  echo "Usage: REGION=... DOMAIN=... OWNER=... REPO_SRC=... [REPO_DST=...] [DRY_RUN=1] $0 /path/to/repository-YYYYMMDDThhmmssZ-1-001.zip"
  exit 2
fi
ZIPFILE="$1"
if [[ ! -f "$ZIPFILE" ]]; then echo "Zip not found: $ZIPFILE"; exit 2; fi

# ======= TOOLING CHECKS =======
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 3; }; }
need aws; need unzip; need mvn

# ======= STAGING / UNZIP =======
ZIP_BASENAME="$(basename "$ZIPFILE")"
STAGE_DIR="$HOME/staging/${ZIP_BASENAME%.zip}"
mkdir -p "$STAGE_DIR"
echo ">> Unzipping to: $STAGE_DIR"
unzip -q -o "$ZIPFILE" -d "$STAGE_DIR"

# Maven-repo root usually ends up as "$STAGE_DIR/repository"
if [[ -d "$STAGE_DIR/repository" ]]; then
  ROOT="$STAGE_DIR/repository"
else
  # Fallback: if the zip contained a top folder 'repository-.../repository'
  ROOT="$(find "$STAGE_DIR" -maxdepth 2 -type d -name repository | head -n1 || true)"
  [[ -n "${ROOT:-}" && -d "$ROOT" ]] || { echo "Could not locate a 'repository/' directory under $STAGE_DIR"; exit 4; }
fi
echo ">> Using repo root: $ROOT"

# ======= CODEARTIFACT AUTH (token-based settings.xml) =======
TOKEN="$(aws codeartifact get-authorization-token \
  --domain "$DOMAIN" --domain-owner "$OWNER" --region "$REGION" \
  --query authorizationToken --output text)"
ENDPOINT_SRC="$(aws codeartifact get-repository-endpoint \
  --domain "$DOMAIN" --domain-owner "$OWNER" --repository "$REPO_SRC" \
  --format maven --region "$REGION" --query repositoryEndpoint --output text)"

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

# ======= HELPERS =======
skip_if_published() {
  local group="$1" artifact="$2" version="$3" repo="$4"
  aws codeartifact list-package-versions \
    --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
    --repository "$repo" --format maven --namespace "$group" --package "$artifact" \
    --query "versions[?version=='$version'].status" --output text 2>/dev/null | grep -q .
}

deploy_file() {
  # args: file pom [classifier] [packagingOverride]
  local file="$1" pom="$2" classifier="${3:-}" packaging="${4:-}"
  local extra=()
  [[ -n "$classifier" ]] && extra+=("-Dclassifier=${classifier}")
  [[ -n "$packaging"  ]] && extra+=("-Dpackaging=${packaging}")
  if [[ "$DRY_RUN" = "1" ]]; then
    echo "DRY-RUN mvn deploy:deploy-file -Dfile=$(basename "$file") $( [[ -n "$classifier" ]] && echo "-Dclassifier=$classifier")"
  else
    mvn -q -s "$SETTINGS" deploy:deploy-file \
      -Durl="$ENDPOINT_SRC" -DrepositoryId=codeartifact \
      -DpomFile="$pom" -Dfile="$file" "${extra[@]}"
  fi
}

copy_to_dst() {
  local group="$1" artifact="$2" version="$3"
  [[ -z "$REPO_DST" ]] && return 0
  if [[ "$DRY_RUN" = "1" ]]; then
    echo "DRY-RUN aws codeartifact copy-package-versions $group:$artifact:$version  $REPO_SRC -> $REPO_DST"
    return 0
  fi
  aws codeartifact copy-package-versions \
    --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
    --source-repository "$REPO_SRC" --destination-repository "$REPO_DST" \
    --format maven --namespace "$group" --package "$artifact" \
    --versions "$version" --allow-overwrite >/dev/null
}

# ======= MAIN LOOP =======
published=0; skipped=0; copied=0; pom_only=0; errors=0

# Find all *.pom that follow the standard layout
# e.g. ROOT/group/path/artifact/version/artifact-version.pom
# We'll use the path to derive G:A:V and pre-check existence.
while IFS= read -r -d '' POM; do
  version_dir="$(dirname "$POM")"             # .../artifact/version
  artifact_dir="$(dirname "$version_dir")"    # .../group/.../artifact
  version="$(basename "$version_dir")"
  artifact="$(basename "$artifact_dir")"
  group_path="${artifact_dir#$ROOT/}"         # group/path
  group_path="${group_path%/$artifact}"       # group/path (without artifact)
  group="${group_path//\//.}"                 # dotted groupId

  # Sanity: filename should contain artifact-version
  if [[ "$(basename "$POM")" != "$artifact-$version.pom" ]]; then
    # Non-canonical; still try, but log it
    echo "!! Non-canonical POM name, proceeding: $POM"
  fi

  # Skip if already present in source repo
  if skip_if_published "$group" "$artifact" "$version" "$REPO_SRC"; then
    ((skipped++)) || true
    echo "-- SKIP (exists) $group:$artifact:$version"
    continue
  fi

  main=""
  for ext in jar war ear zip; do
    cand="$version_dir/$artifact-$version.$ext"
    if [[ -f "$cand" ]]; then main="$cand"; break; fi
  done

  echo ">> PUBLISH $group:$artifact:$version   ($(basename "${main:-POM-only}"))"

  {
    if [[ -n "$main" ]]; then
      # Use existing POM; do not generate a new POM
      deploy_file "$main" "$POM"
      # Optional attached artifacts
      [[ -f "$version_dir/$artifact-$version-sources.jar" ]] && \
        deploy_file "$version_dir/$artifact-$version-sources.jar" "$POM" "sources"
      [[ -f "$version_dir/$artifact-$version-javadoc.jar" ]] && \
        deploy_file "$version_dir/$artifact-$version-javadoc.jar" "$POM" "javadoc"
    else
      # POM-only artifact
      deploy_file "$POM" "$POM" "" "pom"
      ((pom_only++)) || true
    fi

    ((published++)) || true
    # Optional mirror/copy to destination repo
    copy_to_dst "$group" "$artifact" "$version" && [[ -n "$REPO_DST" ]] && ((copied++)) || true
  } || {
    ((errors++)) || true
    echo "!! ERROR publishing $group:$artifact:$version (continuing)"
  }

done < <(find "$ROOT" -type f -name "*.pom" -print0)

echo
echo "===== SUMMARY ====="
echo "Published: $published   (of which POM-only: $pom_only)"
echo "Skipped (already present): $skipped"
[[ -n "$REPO_DST" ]] && echo "Copied to $REPO_DST: $copied"
echo "Errors: $errors"
[[ "$DRY_RUN" = "1" ]] && echo "(Dry run only; nothing actually uploaded.)"