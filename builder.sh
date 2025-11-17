#!/usr/bin/env bash
# Build service images from downloaded JBoss artifacts using a STAGING context.
# Usage: ./builder.sh -s portal|jms|webservice|brms|reporting|apache|all
set -euo pipefail

usage() {
  echo "Usage: $0 -s {portal|jms|webservice|brms|reporting|apache|all}" >&2
  exit 2
}

# ---- Args ----
s=""
while getopts ":s:" opt; do
  case "$opt" in
    s) s="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))
[[ -z "$s" ]] && usage
case "$s" in portal|jms|webservice|brms|reporting|apache|all) ;; *) usage;; esac
echo "[builder] target service: $s"
# ---- Paths & config ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# enable BuildKit for nicer build perf/logs
export DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-0}"

# clean all staging dirs on exit
trap 'rm -rf "$SCRIPT_DIR/.build"' EXIT

shopt -s nullglob

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$SCRIPT_DIR/artifacts}"
BASE_JBOSS_VERSION="${BASE_JBOSS_VERSION:-8.0.8}"
LOCAL_REPO="${LOCAL_REPO:-conexus-jboss}"  # canonical local repo tag (CI will retag to ECR)
ECR_ACCOUNT="${ECR_ACCOUNT:-339713019047}"
ECR_REGION="${ECR_REGION:-us-east-1}"
LEGACY_BASE="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com/conexus-jboss" # compat tag
# Apache repos
LOCAL_APACHE_REPO="${LOCAL_APACHE_REPO:-conexus-apache}"
APACHE_ECR_REPO="${APACHE_ECR_REPO:-conexus-apache}"

# Artifacts: skip only for standalone apache builds
if [[ "$s" == "apache" ]]; then
  :
else
  echo "ARTIFACTS_DIR: $ARTIFACTS_DIR"
  [[ -d "$ARTIFACTS_DIR" ]] || {
    echo "ERROR: artifacts dir not found ($ARTIFACTS_DIR)" >&2
    exit 1
  }
fi

# ---- Helpers ----
pick_latest(){ [[ $# -gt 0 ]] || { echo ""; return 0; }; local files=("$@"); [[ ${#files[@]} -gt 0 ]] || { echo ""; return 0; }; ls -1t "${files[@]}" 2>/dev/null | head -n1 || true; }
want_war(){ pick_latest "${ARTIFACTS_DIR}/$1"-*.war; }   # e.g., want_war 'ui-war'
want_ear(){ pick_latest "${ARTIFACTS_DIR}/$1"-*.ear; }   # e.g., want_ear 'rest-ear'
need_file(){ local label="$1" val="$2" patt="$3"; if [[ -z "$val" ]]; then echo "  ✖ Missing $label (looked for: $patt)"; return 1; fi; echo "  ✔ $label: $(basename "$val")"; }
ver_from(){ local f="$1" base="$2"; echo "$f" | sed -nE "s#^${base}-0[1-2]\\.00\\.000\\.([0-9]+|[0-9]+\\.[0-9]+)-.*#\\1#p"; }

find_dockerfile(){
  local svc="$1"
  for f in \
    "${svc^}Dockerfile" "Dockerfile.${svc}" "Dockerfile-${svc}" \
    "dockerfiles/${svc^}Dockerfile" "dockerfiles/Dockerfile.${svc}" "dockerfiles/Dockerfile-${svc}" \
    "Dockerfile"
  do [[ -f "$f" ]] && { echo "$f"; return 0; }; done
  echo ""
}

prep_stage(){
  # stage_dir dockerfile files...
  local stage="$1"; shift; local df="$1"; shift
  rm -rf "$stage"; mkdir -p "$stage"
  cp "$df" "$stage/$(basename "$df")"
  # keep context tiny & explicit
  printf '%s\n' '*.git' '*.tmp' > "$stage/.dockerignore"
  # copy required artifacts into the context root
  for f in "$@"; do cp "$f" "$stage/$(basename "$f")"; done
  echo "    staged files (context: $stage):"
  (cd "$stage" && ls -la)
  echo "    build cmd: docker build -t <tag> -f $(basename "$df") $stage"
}

build_portal(){
  echo "==> SERVICE: portal"
  echo "    need: ui-war-*.war  +  rest-ear-*.ear"
  local ui rest ui_bn rest_bn ui_v rest_v release tag legacy df stage
  ui="$(want_war 'ui-war')";     need_file "ui-war" "$ui"     "${ARTIFACTS_DIR}/ui-war-*.war"   || return 2
  rest="$(want_ear 'rest-ear')"; need_file "rest-ear" "$rest" "${ARTIFACTS_DIR}/rest-ear-*.ear" || return 2
  ui_bn="$(basename "$ui")"; rest_bn="$(basename "$rest")"
  ui_v="$(ver_from "$ui_bn" 'ui-war')"; rest_v="$(ver_from "$rest_bn" 'rest-ear')"
  [[ -n "$ui_v" && -n "$rest_v" ]] || { echo "  ✖ version parse failed"; return 3; }
  release="${BASE_JBOSS_VERSION}-ui${ui_v}-rest${rest_v}"
  tag="${LOCAL_REPO}:${release}"; legacy="${LEGACY_BASE}-portal:${release}"
  df="$(find_dockerfile portal)"; [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for portal"; return 4; }
  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/portal"; prep_stage "$stage" "$df" "$ui" "$rest"
  docker build -t "$tag" --build-arg="UIWAR=${ui_bn}" --build-arg="RESTEAR=${rest_bn}" -f "$(basename "$df")" "$stage"
  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.portal"
  echo "  Built: $tag"; echo "  Legacy tag: $legacy"
}

build_jms(){
  echo "==> SERVICE: jms"
  echo "    need: task-ear-*.ear"
  local ear ear_bn v release tag legacy df stage
  ear="$(want_ear 'task-ear')"; need_file "task-ear" "$ear" "${ARTIFACTS_DIR}/task-ear-*.ear" || return 2
  ear_bn="$(basename "$ear")"; v="$(ver_from "$ear_bn" 'task-ear')" || true
  [[ -n "$v" ]] || { echo "  ✖ version parse failed"; return 3; }
  release="${BASE_JBOSS_VERSION}-task${v}"
  tag="${LOCAL_REPO}:${release}"; legacy="${LEGACY_BASE}-jms:${release}"
  df="$(find_dockerfile jms)"; [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for jms"; return 4; }
  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/jms"; prep_stage "$stage" "$df" "$ear"
  docker build -t "$tag" --build-arg="TASKEAR=${ear_bn}" -f "$(basename "$df")" "$stage"
  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.jms"
  echo "  Built: $tag"; echo "  Legacy tag: $legacy"
}

build_webservice(){
  echo "==> SERVICE: webservice"
  echo "    need: ws-services-ear-*.ear  cnxs-ws-ear-*.ear  dpa-ear-*.ear"
  local wse cnxs dpa wse_bn cnxs_bn dpa_bn wsv cnxv dpav release tag legacy df stage ok=1
  wse="$(want_ear 'ws-services-ear')"; need_file "ws-services-ear" "$wse" "${ARTIFACTS_DIR}/ws-services-ear-*.ear" || ok=0
  cnxs="$(want_ear 'cnxs-ws-ear')";   need_file "cnxs-ws-ear"    "$cnxs" "${ARTIFACTS_DIR}/cnxs-ws-ear-*.ear"    || ok=0
  dpa="$(want_ear 'dpa-ear')";        need_file "dpa-ear"         "$dpa" "${ARTIFACTS_DIR}/dpa-ear-*.ear"         || ok=0
  [[ $ok -eq 1 ]] || return 2
  wse_bn="$(basename "$wse")"; cnxs_bn="$(basename "$cnxs")"; dpa_bn="$(basename "$dpa")"
  wsv="$(ver_from "$wse_bn" 'ws-services-ear')"; cnxv="$(ver_from "$cnxs_bn" 'cnxs-ws-ear')"; dpav="$(ver_from "$dpa_bn" 'dpa-ear')"
  [[ -n "$wsv" && -n "$cnxv" && -n "$dpav" ]] || { echo "  ✖ version parse failed"; return 3; }
  release="${BASE_JBOSS_VERSION}-ws${wsv}-cnxs${cnxv}-dpa${dpav}"
  tag="${LOCAL_REPO}:${release}"; legacy="${LEGACY_BASE}-webservice:${release}"
  df="$(find_dockerfile webservice)"; [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for webservice"; return 4; }
  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/webservice"; prep_stage "$stage" "$df" "$wse" "$cnxs" "$dpa"
  docker build -t "$tag" \
    --build-arg="WSEAR=${wse_bn}" --build-arg="CNXSEAR=${cnxs_bn}" --build-arg="DPAEAR=${dpa_bn}" \
    -f "$(basename "$df")" "$stage"
  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.webservice"
  echo "  Built: $tag"; echo "  Legacy tag: $legacy"
}

build_brms(){
  echo "==> SERVICE: brms"
  echo "    need: reconciliation-war-*.war  contract-mod-war-*.war  vendor-emulator-war-*.war"
  local recon cmod swag rbn cbn sbn rv cv sv release tag legacy df stage ok=1
  recon="$(want_war 'reconciliation-war')"; need_file "reconciliation-war" "$recon" "${ARTIFACTS_DIR}/reconciliation-war-*.war" || ok=0
  cmod="$(want_war 'contract-mod-war')";    need_file "contract-mod-war"  "$cmod"  "${ARTIFACTS_DIR}/contract-mod-war-*.war"   || ok=0
  swag="$(want_war 'vendor-emulator-war')"; need_file "vendor-emulator-war" "$swag" "${ARTIFACTS_DIR}/vendor-emulator-war-*.war" || ok=0
  [[ $ok -eq 1 ]] || return 2
  rbn="$(basename "$recon")"; cbn="$(basename "$cmod")"; sbn="$(basename "$swag")"
  rv="$(ver_from "$rbn" 'reconciliation-war')"; cv="$(ver_from "$cbn" 'contract-mod-war')"; sv="$(ver_from "$sbn" 'vendor-emulator-war')"
  [[ -n "$rv" && -n "$cv" && -n "$sv" ]] || { echo "  ✖ version parse failed"; return 3; }
  release="${BASE_JBOSS_VERSION}-recon${rv}-cmod${cv}-swag${sv}"
  tag="${LOCAL_REPO}:${release}"; legacy="${LEGACY_BASE}-brms:${release}"
  df="$(find_dockerfile brms)"; [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for brms"; return 4; }
  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/brms"; prep_stage "$stage" "$df" "$recon" "$cmod" "$swag"
  docker build -t "$tag" \
    --build-arg="RECONWAR=${rbn}" --build-arg="CMODWAR=${cbn}" --build-arg="SWAGWAR=${sbn}" \
    -f "$(basename "$df")" "$stage"
  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.brms"
  echo "  Built: $tag"; echo "  Legacy tag: $legacy"
}

build_reporting(){
  echo "==> SERVICE: reporting"
  echo "    need: reporting-war-*.war  vendor-emulator-ear-*.ear"
  local rep vend rbn vbn rv vv release tag legacy df stage ok=1
  rep="$(want_war 'reporting-war')"; need_file "reporting-war" "$rep" "${ARTIFACTS_DIR}/reporting-war-*.war" || ok=0
  vend="$(want_ear 'vendor-emulator-ear')"; need_file "vendor-emulator-ear" "$vend" "${ARTIFACTS_DIR}/vendor-emulator-ear-*.ear" || ok=0
  [[ $ok -eq 1 ]] || return 2
  rbn="$(basename "$rep")"; vbn="$(basename "$vend")"
  rv="$(ver_from "$rbn" 'reporting-war')"; vv="$(ver_from "$vbn" 'vendor-emulator-ear')"
  [[ -n "$rv" && -n "$vv" ]] || { echo "  ✖ version parse failed"; return 3; }
  release="${BASE_JBOSS_VERSION}-repo${rv}-vend${vv}"
  tag="${LOCAL_REPO}:${release}"; legacy="${LEGACY_BASE}-reporting:${release}"
  df="$(find_dockerfile reporting)"; [[ -n "$df" ]] || { echo "  ✖ No Dockerfile for reporting"; return 4; }
  echo "    using Dockerfile: $df"
  stage="$SCRIPT_DIR/.build/reporting"; prep_stage "$stage" "$df" "$rep" "$vend"
  docker build -t "$tag" \
    --build-arg="REPOWAR=${rbn}" --build-arg="VENDEAR=${vbn}" \
    -f "$(basename "$df")" "$stage"
  docker tag "$tag" "$legacy" >/dev/null 2>&1 || true
  echo "$release" > "$SCRIPT_DIR/.release.reporting"
  echo "  Built: $tag"; echo "  Legacy tag: $legacy"
}

build_apache(){
  echo "==> SERVICE: apache"
  # Source lives in the bamboo-deployment repo under devvpc/dockers/apache
  local SRC="${SCRIPT_DIR}/devvpc/dockers/apache"
  [[ -d "$SRC" ]] || { echo "  ✖ Apache source not found: $SRC"; return 4; }

  # Derive a reproducible release tag:
  # - parse Fedora base from Dockerfile (e.g., fedora:42)
  # - hash the contents of configs + html + ui to reflect changes
  local fedver hash release tag ecrtag stage
  fedver="$(sed -nE 's/^FROM[[:space:]]+fedora:([0-9]+).*/\1/p' "$SRC/Dockerfile" | head -1 || true)"
  fedver="${fedver:-42}"
  hash="$(
    ( cd "$SRC" && \
      { find . -maxdepth 1 -type f -print0 2>/dev/null; \
        find html -type f -print0 2>/dev/null; \
        find conexus-ui-public -type f -print0 2>/dev/null; } \
      | xargs -0 sha1sum ) | sha1sum | cut -c1-7
  )"
  release="httpd${fedver}-${hash}"
  tag="${LOCAL_APACHE_REPO}:${release}"
  ecrtag="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com/${APACHE_ECR_REPO}:${release}"

  # Stage a tight build context
  stage="$SCRIPT_DIR/.build/apache"
  rm -rf "$stage"; mkdir -p "$stage"

  cp "$SRC/Dockerfile" "$stage/Dockerfile"
  cp "$SRC"/*.conf "$stage"/
  if [[ -d "$SRC/html" ]]; then cp -a "$SRC/html" "$stage/html"; fi
  if [[ -d "$SRC/conexus-ui-public" ]]; then cp -a "$SRC/conexus-ui-public" "$stage/conexus-ui-public"; fi
  if [[ -f "$SRC/maintenance.html" ]]; then cp "$SRC/maintenance.html" "$stage/maintenance.html"; fi
  printf '%s\n' '*.git' '*.tmp' > "$stage/.dockerignore"

  echo "    staged files (context: $stage):"; (cd "$stage" && ls -la)

  # *** Important: point docker explicitly at the staged Dockerfile ***
  docker build -t "$tag" -f "$stage/Dockerfile" "$stage"

  docker tag "$tag" "$ecrtag"

  echo "$release" > "$SCRIPT_DIR/.release.apache"
  echo "  Built: $tag"
  echo "  ECR tag (local retag): $ecrtag"
}

# ---- Orchestration ----
services=( "$s" ); [[ "$s" == "all" ]] && services=( portal jms webservice brms reporting apache )
overall_rc=0; built=()

for svc in "${services[@]}"; do
  rc=0
  case "$svc" in
    portal)      build_portal      || rc=$? ;;
    jms)         build_jms         || rc=$? ;;
    webservice)  build_webservice  || rc=$? ;;
    brms)        build_brms        || rc=$? ;;
    reporting)   build_reporting   || rc=$? ;;
    apache)      build_apache      || rc=$? ;;
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
  printf 'Release files: '; for b in "${built[@]}"; do printf '.release.%s ' "$b"; done; echo
else
  echo "No services were built."
fi

exit "$overall_rc"