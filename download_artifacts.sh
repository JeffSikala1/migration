#!/usr/bin/env bash
# Download latest EAR/WAR artifacts from Artifactory Maven repos using direct Maven metadata.
# No dependency on Artifactory latestVersion or repositories APIs.
#
# Supports:
#   - explicit coords via INCLUDE_COORDS
#   - package mode via INCLUDE_PACKAGES + NAMESPACE_PREFIX
#   - explicit version hints via VERSION_HINTS
#   - snapshot resolution via maven-metadata.xml
#   - repo failover via INCLUDE_REPOS order
#
# should look like this when running:
#   export INCLUDE_COORDS="gov.gsa.cnxs.reconciliation:reconciliation-war,gov.gsa.cnxs.ws:ws-services-ear"
#   export VERSION_HINTS="gov.gsa.cnxs.reconciliation:reconciliation-war:02.00.000.148-SNAPSHOT,gov.gsa.cnxs.ws:ws-services-ear:02.00.000.152-SNAPSHOT"
#   export INCLUDE_REPOS="conexus-snapshot-local,conexus-plugin-repository"
#   bash download_artifacts.sh

set -euo pipefail

###############################################
# Defaults (override via env)
###############################################
ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"
ARTIFACTORY_USER="${ARTIFACTORY_USER:-sa_bamboo}"
ARTIFACTORY_TOKEN="${ARTIFACTORY_TOKEN:-${bamboo_artifactory_access_token_secret:-}}"

DL_DIR="${DL_DIR:-./artifacts}"

# Used only when INCLUDE_PACKAGES is provided instead of INCLUDE_COORDS
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-gov.gsa.cnxs}"

# Ordered repo list, first hit wins
INCLUDE_REPOS="${INCLUDE_REPOS:-conexus-snapshot-local,conexus-plugin-repository}"

# Optional skip list
SKIP_REPOS="${SKIP_REPOS:-}"

# Either use full coords:
#   gov.gsa.cnxs.reconciliation:reconciliation-war,gov.gsa.cnxs.ws:ws-services-ear
INCLUDE_COORDS="${INCLUDE_COORDS:-}"

# Or artifactIds with a shared group prefix:
#   reconciliation-war,ws-services-ear
INCLUDE_PACKAGES="${INCLUDE_PACKAGES:-}"

# Optional explicit version hints:
#   group:artifact:version,group:artifact:version
VERSION_HINTS="${VERSION_HINTS:-}"

# Optional regex to filter versions if discovered from metadata
VERSION_REGEX="${VERSION_REGEX:-}"

# Allowed extensions
PREFERRED_EXTS="${PREFERRED_EXTS:-ear,war}"

###############################################
# Requirements
###############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need curl
need awk
need sed
need sort
need grep
need head

mkdir -p "$DL_DIR"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { err "$*"; exit 1; }

[[ -n "$ARTIFACTORY_TOKEN" ]] || die "ARTIFACTORY_TOKEN is empty. Set ARTIFACTORY_TOKEN or bamboo_artifactory_access_token_secret."

log "Starting artifact download"
log "Target directory: $DL_DIR"

###############################################
# Curl helpers
###############################################
curl_text() {
  local url="$1"
  curl -fsSL \
    --retry 4 --retry-delay 2 \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    "$url"
}

curl_head_ok() {
  local url="$1"
  curl -fsI \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    "$url" >/dev/null 2>&1
}

curl_download() {
  local url="$1" out="$2"
  curl -fSL \
    --retry 5 --retry-delay 2 \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    -o "$out" \
    "$url"
}

###############################################
# Maps
###############################################
declare -A WANT_COORD=()
declare -A WANT_PKG=()
declare -A WANT_REPO=()
declare -A SKIP_REPO_MAP=()
declare -A OKEXT=()
declare -A VERSION_HINT_MAP=()

IFS=',' read -r -a _repos <<< "$INCLUDE_REPOS"
for r in "${_repos[@]}"; do
  r="${r// /}"
  [[ -n "$r" ]] && WANT_REPO["$r"]=1
done

IFS=',' read -r -a _skip <<< "$SKIP_REPOS"
for r in "${_skip[@]}"; do
  r="${r// /}"
  [[ -n "$r" ]] && SKIP_REPO_MAP["$r"]=1
done

IFS=',' read -r -a _coords <<< "$INCLUDE_COORDS"
for c in "${_coords[@]}"; do
  c="${c// /}"
  [[ -n "$c" ]] && WANT_COORD["$c"]=1
done

IFS=',' read -r -a _pkgs <<< "$INCLUDE_PACKAGES"
for p in "${_pkgs[@]}"; do
  p="${p// /}"
  [[ -n "$p" ]] && WANT_PKG["$p"]=1
done

IFS=',' read -r -a _hints <<< "$VERSION_HINTS"
for h in "${_hints[@]}"; do
  h="${h// /}"
  [[ -z "$h" ]] && continue

  group="${h%%:*}"
  rest="${h#*:}"
  artifact="${rest%%:*}"
  version="${rest#*:}"

  if [[ -n "$group" && -n "$artifact" && -n "$version" && "$version" != "$rest" ]]; then
    VERSION_HINT_MAP["${group}:${artifact}"]="$version"
  else
    warn "Ignoring invalid VERSION_HINTS entry: $h"
  fi
done

IFS=',' read -r -a _exts <<< "$PREFERRED_EXTS"
for e in "${_exts[@]}"; do
  e="${e// /}"
  [[ -n "$e" ]] && OKEXT["$e"]=1
done

###############################################
# Helpers
###############################################
trim() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

group_to_path() {
  local group="$1"
  echo "${group//./\/}"
}

artifact_metadata_url() {
  local repo="$1" group="$2" artifact="$3"
  local group_path
  group_path="$(group_to_path "$group")"
  echo "${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/maven-metadata.xml"
}

version_metadata_url() {
  local repo="$1" group="$2" artifact="$3" version="$4"
  local group_path
  group_path="$(group_to_path "$group")"
  echo "${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/${version}/maven-metadata.xml"
}

extract_latest_version_from_artifact_metadata() {
  local xml="$1"
  local v

  v="$(sed -n 's:.*<latest>\(.*\)</latest>.*:\1:p' <<< "$xml" | head -n1 | trim)"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
    return 0
  fi

  v="$(sed -n 's:.*<release>\(.*\)</release>.*:\1:p' <<< "$xml" | head -n1 | trim)"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
    return 0
  fi

  v="$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' <<< "$xml" | tail -n1 | trim)"
  [[ -n "$v" ]] && printf '%s' "$v"
}

resolve_version_for_coord() {
  local repo="$1" group="$2" artifact="$3"
  local key="${group}:${artifact}"

  if [[ -n "${VERSION_HINT_MAP[$key]+x}" ]]; then
    printf '%s' "${VERSION_HINT_MAP[$key]}"
    return 0
  fi

  local meta_url xml v
  meta_url="$(artifact_metadata_url "$repo" "$group" "$artifact")"
  xml="$(curl_text "$meta_url" 2>/dev/null || true)"
  [[ -n "$xml" ]] || return 1

  v="$(extract_latest_version_from_artifact_metadata "$xml" || true)"
  [[ -n "$v" ]] || return 1

  if [[ -n "$VERSION_REGEX" ]] && ! printf '%s' "$v" | grep -Eq "$VERSION_REGEX"; then
    return 1
  fi

  printf '%s' "$v"
}

snapshot_candidates_from_metadata() {
  local artifact="$1" xml="$2"

  awk '
    /<snapshotVersion>/ { in_block=1; val=""; ext="" }
    in_block && /<value>/ {
      gsub(/.*<value>|<\/value>.*/, "", $0)
      val=$0
    }
    in_block && /<extension>/ {
      gsub(/.*<extension>|<\/extension>.*/, "", $0)
      ext=$0
    }
    in_block && /<\/snapshotVersion>/ {
      if (val != "" && ext != "") print val "|" ext
      in_block=0; val=""; ext=""
    }
  ' <<< "$xml" | while IFS='|' read -r val ext; do
    [[ -n "${OKEXT[$ext]+x}" ]] && echo "${artifact}-${val}.${ext}"
  done

  local ts bn
  ts="$(sed -n 's:.*<timestamp>\(.*\)</timestamp>.*:\1:p' <<< "$xml" | head -n1 | trim)"
  bn="$(sed -n 's:.*<buildNumber>\(.*\)</buildNumber>.*:\1:p' <<< "$xml" | head -n1 | trim)"

  if [[ -n "$ts" && -n "$bn" ]]; then
    for e in "${!OKEXT[@]}"; do
      echo "${artifact}-${CURRENT_VERSION%-SNAPSHOT}-${ts}-${bn}.${e}"
    done
  fi
}

release_candidates() {
  local artifact="$1" version="$2"
  if [[ "$artifact" == *-war ]]; then
    echo "${artifact}-${version}.war"
  elif [[ "$artifact" == *-ear ]]; then
    echo "${artifact}-${version}.ear"
  else
    for e in "${!OKEXT[@]}"; do
      echo "${artifact}-${version}.${e}"
    done
  fi
}

###############################################
# Build repo list in order
###############################################
REPO_LIST=()
IFS=',' read -r -a _ordered_repos <<< "$INCLUDE_REPOS"
for r in "${_ordered_repos[@]}"; do
  r="${r// /}"
  [[ -z "$r" ]] && continue
  [[ -n "${SKIP_REPO_MAP[$r]+x}" ]] && continue
  REPO_LIST+=( "$r" )
done

[[ ${#REPO_LIST[@]} -gt 0 ]] || die "No repos available after applying INCLUDE_REPOS/SKIP_REPOS."

###############################################
# Build coordinate list
###############################################
declare -A COORDS=()

if [[ ${#WANT_COORD[@]} -gt 0 ]]; then
  for c in "${!WANT_COORD[@]}"; do
    COORDS["$c"]=1
  done
elif [[ ${#WANT_PKG[@]} -gt 0 ]]; then
  for p in "${!WANT_PKG[@]}"; do
    COORDS["${NAMESPACE_PREFIX}:${p}"]=1
  done
else
  die "Set INCLUDE_COORDS or INCLUDE_PACKAGES."
fi

###############################################
# Main download loop
###############################################
declare -A DOWNLOADED=()
failures=0

for key in "${!COORDS[@]}"; do
  group="${key%%:*}"
  artifact="${key##*:}"

  [[ -n "${DOWNLOADED[$key]+x}" ]] && continue
  success=0

  for repo in "${REPO_LIST[@]}"; do
    version="$(resolve_version_for_coord "$repo" "$group" "$artifact" || true)"
    [[ -n "$version" ]] || continue

    CURRENT_VERSION="$version"
    group_path="$(group_to_path "$group")"
    base="${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/${version}"

    filenames=()

    if [[ "$version" == *-SNAPSHOT ]]; then
      meta_url="$(version_metadata_url "$repo" "$group" "$artifact" "$version")"
      xml="$(curl_text "$meta_url" 2>/dev/null || true)"

      if [[ -n "$xml" ]]; then
        while IFS= read -r f; do
          [[ -n "$f" ]] && filenames+=( "$f" )
        done < <(snapshot_candidates_from_metadata "$artifact" "$xml")
      fi

      if ((${#filenames[@]} == 0)); then
        for e in "${!OKEXT[@]}"; do
          filenames+=( "${artifact}-${version}.${e}" )
          filenames+=( "${artifact}-${version%-SNAPSHOT}.${e}" )
        done
      fi
    else
      while IFS= read -r f; do
        [[ -n "$f" ]] && filenames+=( "$f" )
      done < <(release_candidates "$artifact" "$version")
    fi

    got=""
    for f in "${filenames[@]}"; do
      ext="${f##*.}"
      [[ -n "${OKEXT[$ext]+x}" ]] || continue
      url="${base}/${f}"
      if curl_head_ok "$url"; then
        got="$url"
        break
      fi
    done

    [[ -n "$got" ]] || continue

    out="${DL_DIR}/$(basename "$got")"
    log "Downloading $(basename "$got")"

    if curl_download "$got" "$out"; then
      DOWNLOADED["$key"]=1
      success=1
      break
    else
      err "[${group}:${artifact}] download failed from repo=${repo}"
      rm -f "$out" || true
    fi
  done

  if [[ $success -ne 1 ]]; then
    warn "[${group}:${artifact}] unable to fetch from any repo"
    failures=$((failures + 1))
  fi
done

log "Done. Artifacts stored in $DL_DIR"

if [[ $failures -gt 0 ]]; then
  err "Completed with ${failures} artifact failure(s)."
  exit 1
fi