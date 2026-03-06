#!/usr/bin/env bash
# Build service images from downloaded artifacts using a staging context.
# Usage: ./builder.sh -s portal|jms|webservice|brms|reporting|apache|wso2|all

set -euo pipefail

usage() {
  echo "Usage: $0 -s {portal|jms|webservice|brms|reporting|apache|wso2|all}" >&2
  exit 2
}

s=""
while getopts ":s:" opt; do
  case "$opt" in
    s) s="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

[[ -n "$s" ]] || usage
case "$s" in
  portal|jms|webservice|brms|reporting|apache|wso2|all) ;;
  *) usage ;;
esac

echo "[builder] target service: $s"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# Enable BuildKit by default
export DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"

trap 'rm -rf "$SCRIPT_DIR/.build"' EXIT
shopt -s nullglob

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$SCRIPT_DIR/artifacts}"
BASE_JBOSS_VERSION="${BASE_JBOSS_VERSION:-8.0.8}"

LOCAL_REPO="${LOCAL_REPO:-conexus-jboss}"

ECR_ACCOUNT="${ECR_ACCOUNT:-339713019047}"
ECR_REGION="${ECR_REGION:-us-east-1}"
LEGACY_BASE="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com/conexus-jboss"

LOCAL_APACHE_REPO="${LOCAL_APACHE_REPO:-conexus-apache-oidc}"
APACHE_ECR_REPO="${APACHE_ECR_REPO:-conexus-apache-oidc}"

LOCAL_WSO2_REPO="${LOCAL_WSO2_REPO:-conexus-wso2mi}"
WSO2_ECR_REPO="${WSO2_ECR_REPO:-conexus-wso2mi}"

if [[ "$s" != "apache" ]]; then
  echo "ARTIFACTS_DIR: $ARTIFACTS_DIR"
  [[ -d "$ARTIFACTS_DIR" ]] || {
    echo "ERROR: artifacts dir not found ($ARTIFACTS_DIR)" >&2
    exit 1
  }
fi

pick_latest() {
  [[ $# -gt 0 ]] || { echo ""; return 0; }
  local files=("$@")
  [[ ${#files[@]} -gt 0 ]] || { echo ""; return 0; }
  ls -1t "${files[@]}" 2>/dev/null | head -n1 || true
}

want_war() { pick_latest "${ARTIFACTS_DIR}/$1"-*.war; }
want_ear() { pick_latest "${ARTIFACTS_DIR}/$1"-*.ear; }

need_file() {
  local label="$1" val="$2" patt="$3"
  if [[ -z "$val" ]]; then
    echo "  ✖ Missing $label (looked for: $patt)"
    return 1
  fi
  echo "  ✔ $label: $(basename "$val")"
}

# Extract Maven version from artifact file name:
#   artifactId-<version>.war
#   artifactId-<version>.ear
# Returns full version string, not just patch.
full_version_from() {
  local file="$1" artifact="$2"
  local bn
  bn="$(basename "$file")"
  bn="${bn%.war}"
  bn="${bn%.ear}"
  bn="${bn#${artifact}-}"
  printf '%s\n' "$bn"
}

# Short numeric build token used in your current image release format
# Example:
#   reconciliation-war-02.00.000.148-SNAPSHOT.war -> 148
#   ws-client-02.00.000.144-20260305.164656-47.jar -> 144
short_version_token() {
  local file="$1" artifact="$2"
  local v
  v="$(full_version_from "$file" "$artifact")"
  printf '%s\n' "$v" | sed -nE 's#^[0-9]+\.[0-9]+\.[0-9]+\.([0-9]+).*$#\1#p'
}

find_dockerfile() {
  local svc="$1"
  for f in \
    "${svc^}Dockerfile" "Dockerfile.${svc}" "Dockerfile-${svc}" \
    "dockerfiles/${svc^}Dockerfile" "dockerfiles/Dockerfile.${svc}" "dockerfiles/Dockerfile-${svc}" \
    "Dockerfile"
  do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  echo ""
}

prep_stage() {
  local stage="$1"; shift
  local df="$1"; shift

  rm -rf "$stage"
  mkdir -p "$stage"

  cp "$df" "$stage/$(basename "$df")"
  printf '%s\n' '*.git' '*.tmp' > "$stage/.dockerignore"

  for f in "$@"; do
    cp "$f" "$stage/$(basename "$f")"
  done

  echo "    staged files (context: $stage):"
  (cd "$stage" && ls -la)
}

next_numeric_tag() {
  local repo="$1"
  local raw_tags max_tag major minor

  raw_tags="$(aws ecr describe-images \
      --repository-name "$repo" \
      --region "$ECR_REGION" \
      --query 'imageDetails[].imageTags[]' \
      --output text 2>/dev/null || true)"

  max_tag="$(
    printf '%s\n' ${raw_tags:-} \
      | grep -E '^[0-9]+\.[0-9]+$' \
      | sort -V \
      | tail -n1
  )"

  if [[ -z "$max_tag" ]]; then
    echo "1.0"
    return 0
  fi

  IFS='.' read -r major minor <<< "$max_tag"
  minor=$((minor + 1))
  echo "${major}.${minor}"
}

build_portal() {
  echo "==> SERVICE: portal"
  local ui rest ui_bn rest_bn ui_v rest_v release tag legacy df stage

  ui="$(want_war 'ui-war')"
  need_file "ui-war" "$ui" "${ARTIFACTS_DIR}/ui-war-*.war" || return 2

  rest="$(want_ear 'rest-ear')"
  need_file "rest-ear" "$rest" "${ARTIFACTS_DIR}/rest-ear-*.ear" || return 2

  ui_bn="$(basename "$ui")"
  rest_bn="$(basename "$rest")"

  ui_v="$(short_version_token "$ui" 'ui-war')"
  rest_v="$(short_version_token "$rest" 'rest-ear')"

  [[ -n "$ui_v" && -n "$rest_v" ]] || { echo "  ✖ version parse failed"; return 3; }

  release="${BASE_JBOSS_VERSION}-ui${ui_v}-rest${rest_v}"
  tag="${LOCAL_REPO}:${release}"
  legacy="${LEGACY_BASE}-portal:${release}"

  df="$(find_dockerfile portal)"
  [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for portal"; return 4; }

  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/portal"
  prep_stage "$stage" "$df" "$ui" "$rest"

  docker build -t "$tag" \
    --build-arg="UIWAR=${ui_bn}" \
    --build-arg="RESTEAR=${rest_bn}" \
    -f "$(basename "$df")" "$stage"

  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.portal"

  echo "  Built: $tag"
  echo "  Legacy tag: $legacy"
}

build_jms() {
  echo "==> SERVICE: jms"
  local ear ear_bn v release tag legacy df stage

  ear="$(want_ear 'task-ear')"
  need_file "task-ear" "$ear" "${ARTIFACTS_DIR}/task-ear-*.ear" || return 2

  ear_bn="$(basename "$ear")"
  v="$(short_version_token "$ear" 'task-ear')"
  [[ -n "$v" ]] || { echo "  ✖ version parse failed"; return 3; }

  release="${BASE_JBOSS_VERSION}-task${v}"
  tag="${LOCAL_REPO}:${release}"
  legacy="${LEGACY_BASE}-jms:${release}"

  df="$(find_dockerfile jms)"
  [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for jms"; return 4; }

  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/jms"
  prep_stage "$stage" "$df" "$ear"

  docker build -t "$tag" \
    --build-arg="TASKEAR=${ear_bn}" \
    -f "$(basename "$df")" "$stage"

  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.jms"

  echo "  Built: $tag"
  echo "  Legacy tag: $legacy"
}

build_webservice() {
  echo "==> SERVICE: webservice"
  local wse cnxs dpa wse_bn cnxs_bn dpa_bn wsv cnxv dpav release tag legacy df stage ok=1

  wse="$(want_ear 'ws-services-ear')"
  need_file "ws-services-ear" "$wse" "${ARTIFACTS_DIR}/ws-services-ear-*.ear" || ok=0

  cnxs="$(want_ear 'cnxs-ws-ear')"
  need_file "cnxs-ws-ear" "$cnxs" "${ARTIFACTS_DIR}/cnxs-ws-ear-*.ear" || ok=0

  dpa="$(want_ear 'dpa-ear')"
  need_file "dpa-ear" "$dpa" "${ARTIFACTS_DIR}/dpa-ear-*.ear" || ok=0

  [[ $ok -eq 1 ]] || return 2

  wse_bn="$(basename "$wse")"
  cnxs_bn="$(basename "$cnxs")"
  dpa_bn="$(basename "$dpa")"

  wsv="$(short_version_token "$wse" 'ws-services-ear')"
  cnxv="$(short_version_token "$cnxs" 'cnxs-ws-ear')"
  dpav="$(short_version_token "$dpa" 'dpa-ear')"

  [[ -n "$wsv" && -n "$cnxv" && -n "$dpav" ]] || { echo "  ✖ version parse failed"; return 3; }

  release="${BASE_JBOSS_VERSION}-ws${wsv}-cnxs${cnxv}-dpa${dpav}"
  tag="${LOCAL_REPO}:${release}"
  legacy="${LEGACY_BASE}-webservice:${release}"

  df="$(find_dockerfile webservice)"
  [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for webservice"; return 4; }

  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/webservice"
  prep_stage "$stage" "$df" "$wse" "$cnxs" "$dpa"

  docker build -t "$tag" \
    --build-arg="WSEAR=${wse_bn}" \
    --build-arg="CNXSEAR=${cnxs_bn}" \
    --build-arg="DPAEAR=${dpa_bn}" \
    -f "$(basename "$df")" "$stage"

  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.webservice"

  echo "  Built: $tag"
  echo "  Legacy tag: $legacy"
}

build_brms() {
  echo "==> SERVICE: brms"
  local recon cmod swag rbn cbn sbn rv cv sv release tag legacy df stage ok=1

  recon="$(want_war 'reconciliation-war')"
  need_file "reconciliation-war" "$recon" "${ARTIFACTS_DIR}/reconciliation-war-*.war" || ok=0

  cmod="$(want_war 'contract-mod-war')"
  need_file "contract-mod-war" "$cmod" "${ARTIFACTS_DIR}/contract-mod-war-*.war" || ok=0

  swag="$(want_war 'vendor-emulator-war')"
  need_file "vendor-emulator-war" "$swag" "${ARTIFACTS_DIR}/vendor-emulator-war-*.war" || ok=0

  [[ $ok -eq 1 ]] || return 2

  rbn="$(basename "$recon")"
  cbn="$(basename "$cmod")"
  sbn="$(basename "$swag")"

  rv="$(short_version_token "$recon" 'reconciliation-war')"
  cv="$(short_version_token "$cmod" 'contract-mod-war')"
  sv="$(short_version_token "$swag" 'vendor-emulator-war')"

  [[ -n "$rv" && -n "$cv" && -n "$sv" ]] || { echo "  ✖ version parse failed"; return 3; }

  release="${BASE_JBOSS_VERSION}-recon${rv}-cmod${cv}-swag${sv}"
  tag="${LOCAL_REPO}:${release}"
  legacy="${LEGACY_BASE}-brms:${release}"

  df="$(find_dockerfile brms)"
  [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for brms"; return 4; }

  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/brms"
  prep_stage "$stage" "$df" "$recon" "$cmod" "$swag"

  docker build -t "$tag" \
    --build-arg="RECONWAR=${rbn}" \
    --build-arg="CMODWAR=${cbn}" \
    --build-arg="SWAGWAR=${sbn}" \
    -f "$(basename "$df")" "$stage"

  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.brms"

  echo "  Built: $tag"
  echo "  Legacy tag: $legacy"
}

build_reporting() {
  echo "==> SERVICE: reporting"
  local rep vend rbn vbn rv vv release tag legacy df stage ok=1

  rep="$(want_war 'reporting-war')"
  need_file "reporting-war" "$rep" "${ARTIFACTS_DIR}/reporting-war-*.war" || ok=0

  vend="$(want_ear 'vendor-emulator-ear')"
  need_file "vendor-emulator-ear" "$vend" "${ARTIFACTS_DIR}/vendor-emulator-ear-*.ear" || ok=0

  [[ $ok -eq 1 ]] || return 2

  rbn="$(basename "$rep")"
  vbn="$(basename "$vend")"

  rv="$(short_version_token "$rep" 'reporting-war')"
  vv="$(short_version_token "$vend" 'vendor-emulator-ear')"

  [[ -n "$rv" && -n "$vv" ]] || { echo "  ✖ version parse failed"; return 3; }

  release="${BASE_JBOSS_VERSION}-repo${rv}-vend${vv}"
  tag="${LOCAL_REPO}:${release}"
  legacy="${LEGACY_BASE}-reporting:${release}"

  df="$(find_dockerfile reporting)"
  [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for reporting"; return 4; }

  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/reporting"
  prep_stage "$stage" "$df" "$rep" "$vend"

  docker build -t "$tag" \
    --build-arg="REPOWAR=${rbn}" \
    --build-arg="VENDEAR=${vbn}" \
    -f "$(basename "$df")" "$stage"

  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.reporting"

  echo "  Built: $tag"
  echo "  Legacy tag: $legacy"
}

build_apache() {
  echo "==> SERVICE: apache"

  local SRC="${SCRIPT_DIR}/../scripts/devvpc/dockers/apache"
  [[ -d "$SRC" ]] || { echo "  ✖ Apache source not found: $SRC"; return 4; }

  local release tag ecrtag stage
  release="$(next_numeric_tag "$APACHE_ECR_REPO")"
  tag="${LOCAL_APACHE_REPO}:${release}"
  ecrtag="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com/${APACHE_ECR_REPO}:${release}"

  stage="$SCRIPT_DIR/.build/apache"
  rm -rf "$stage"
  mkdir -p "$stage"

  cp "$SRC/Dockerfile" "$stage/Dockerfile"
  compgen -G "$SRC/*.conf" >/dev/null && cp "$SRC"/*.conf "$stage"/
  [[ -d "$SRC/html" ]] && cp -a "$SRC/html" "$stage/html"
  [[ -d "$SRC/conexus-ui-public" ]] && cp -a "$SRC/conexus-ui-public" "$stage/conexus-ui-public"
  [[ -f "$SRC/maintenance.html" ]] && cp "$SRC/maintenance.html" "$stage/maintenance.html"
  printf '%s\n' '*.git' '*.tmp' > "$stage/.dockerignore"

  echo "    staged files (context: $stage):"
  (cd "$stage" && ls -la)

  docker build -t "$tag" -f "$stage/Dockerfile" "$stage"
  docker tag "$tag" "$ecrtag"

  echo "$release" > "$SCRIPT_DIR/.release.apache"
  echo "  Built: $tag"
  echo "  ECR tag: $ecrtag"
}

build_wso2() {
  echo "==> SERVICE: wso2"

  local car_dir="${ARTIFACTS_DIR:-$SCRIPT_DIR/artifacts}"
  compgen -G "${car_dir}/*.car" >/dev/null || { echo "  ✖ No .car artifacts found in ${car_dir}"; return 2; }

  local cars=()
  mapfile -t cars < <(ls -1 "${car_dir}"/*.car 2>/dev/null || true)
  [[ ${#cars[@]} -gt 0 ]] || { echo "  ✖ No .car artifacts found in ${car_dir}"; return 2; }

  local SRC="${SCRIPT_DIR}/../scripts/devvpc/dockers/wso2"
  [[ -d "$SRC" ]] || { echo "  ✖ WSO2 Dockerfile source not found: $SRC"; return 4; }

  local release tag ecrtag stage
  release="$(next_numeric_tag "$WSO2_ECR_REPO")"
  tag="${LOCAL_WSO2_REPO}:${release}"
  ecrtag="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com/${WSO2_ECR_REPO}:${release}"

  stage="$SCRIPT_DIR/.build/wso2"
  rm -rf "$stage"
  mkdir -p "$stage"

  cp "$SRC/Dockerfile" "$stage/Dockerfile"
  cp "${cars[@]}" "$stage/"
  printf '%s\n' '*.git' '*.tmp' > "$stage/.dockerignore"

  echo "    staged files (context: $stage):"
  (cd "$stage" && ls -la)

  docker build -t "$tag" -f "$stage/Dockerfile" "$stage"
  docker tag "$tag" "$ecrtag"

  echo "$release" > "$SCRIPT_DIR/.release.wso2"
  echo "  Built: $tag"
  echo "  ECR tag: $ecrtag"
}

services=( "$s" )
[[ "$s" == "all" ]] && services=( portal jms webservice brms reporting apache wso2 )

overall_rc=0
built=()

for svc in "${services[@]}"; do
  rc=0
  case "$svc" in
    portal)      build_portal      || rc=$? ;;
    jms)         build_jms         || rc=$? ;;
    webservice)  build_webservice  || rc=$? ;;
    brms)        build_brms        || rc=$? ;;
    reporting)   build_reporting   || rc=$? ;;
    apache)      build_apache      || rc=$? ;;
    wso2)        build_wso2        || rc=$? ;;
  esac

  if [[ $rc -eq 0 ]]; then
    [[ -f ".release.$svc" ]] && built+=( "$svc" )
  else
    overall_rc=$(( overall_rc | rc ))
    echo "  -> Skipped/failed: $svc (rc=$rc)"
  fi
done

echo "---- Summary ----"
if ((${#built[@]})); then
  echo "Built services: ${built[*]}"
  printf 'Release files: '
  for b in "${built[@]}"; do
    printf '.release.%s ' "$b"
  done
  echo
else
  echo "No services were built."
fi

exit "$overall_rc"