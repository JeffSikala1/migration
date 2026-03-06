#!/usr/bin/env bash
# Download latest EAR/WAR artifacts from Artifactory Maven repos.
# Supports release + SNAPSHOT resolution, repo ordering, and deterministic package selection.

set -euo pipefail
[[ "${DEBUG:-}" == "1" ]] && set -x

###############################################
# Defaults (override via env)
###############################################
ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"
ARTIFACTORY_USER="${ARTIFACTORY_USER:-sa_bamboo}"
ARTIFACTORY_TOKEN="${ARTIFACTORY_TOKEN:-${bamboo_artifactory_access_token_secret:-}}"

DL_DIR="${DL_DIR:-./artifacts}"

# Primary group prefix for INCLUDE_PACKAGES mode
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-gov.gsa.cnxs}"

# Optional regex filter for version returned by latestVersion API
# Example: SNAPSHOT|RC
VERSION_REGEX="${VERSION_REGEX:-}"

# Preferred repo order for Artifactory migration
# Put snapshot-local first so branch/SNAPSHOT builds resolve there first.
INCLUDE_REPOS="${INCLUDE_REPOS:-conexus-snapshot-local,conexus-plugin-repository}"

# Optional skip list
SKIP_REPOS="${SKIP_REPOS:-}"

# Optional explicit artifactIds, comma-separated
# Example: task-ear,ws-services-ear,reconciliation-war
INCLUDE_PACKAGES="${INCLUDE_PACKAGES:-}"

# Optional explicit full Maven coordinates, comma-separated
# Example: gov.gsa.cnxs.reconciliation:reconciliation-war,gov.gsa.cnxs.ws:ws-services-ear
INCLUDE_COORDS="${INCLUDE_COORDS:-}"

# Allowed extensions
PREFERRED_EXTS="${PREFERRED_EXTS:-ear,war}"

# AQL discovery cap if INCLUDE_PACKAGES is not set
DISCOVERY_LIMIT="${DISCOVERY_LIMIT:-5000}"

###############################################
# Requirements
###############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need jq
need curl
need awk
need sed
need sort

mkdir -p "$DL_DIR"

log()  { printf '[%s] %s\n'   "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN: %s\n'  "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { err "$*"; exit 1; }

[[ -n "$ARTIFACTORY_TOKEN" ]] || die "ARTIFACTORY_TOKEN is empty. Set bamboo_artifactory_access_token_secret or ARTIFACTORY_TOKEN."

log "Using ARTIFACTORY_BASE_URL=$ARTIFACTORY_BASE_URL as user=$ARTIFACTORY_USER"
log "DL_DIR=$DL_DIR NAMESPACE_PREFIX=$NAMESPACE_PREFIX VERSION_REGEX=${VERSION_REGEX:-<none>} PREFERRED_EXTS=$PREFERRED_EXTS"
[[ -n "$INCLUDE_REPOS"   ]] && log "INCLUDE_REPOS=$INCLUDE_REPOS"
[[ -n "$SKIP_REPOS"      ]] && log "SKIP_REPOS=$SKIP_REPOS"
[[ -n "$INCLUDE_PACKAGES" ]] && log "INCLUDE_PACKAGES=$INCLUDE_PACKAGES"
[[ -n "$INCLUDE_COORDS" ]] && log "INCLUDE_COORDS=$INCLUDE_COORDS"
log "DEBUG mode enabled: ${DEBUG:-0}"
log "Using repos: ${INCLUDE_REPOS:-<auto>}"
log "Using packages: ${INCLUDE_PACKAGES:-<discovery>}"

###############################################
# Curl helpers
###############################################
curl_json() {
  local url="$1"
  curl -fsSL \
    --retry 4 --retry-delay 2 \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    -H 'Accept: application/json' \
    "$url"
}

curl_xml() {
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
# Build allow/deny maps
###############################################
declare -A ALLOW_REPO=()
declare -A SKIP_REPO_MAP=()
declare -A WANT_COORD=()
declare -A WANT_PKG=()
declare -A OKEXT=()

IFS=',' read -r -a _allow <<< "$INCLUDE_REPOS"
for r in "${_allow[@]}"; do
  r="${r// /}"
  [[ -n "$r" ]] && ALLOW_REPO["$r"]=1
done

IFS=',' read -r -a _skip <<< "$SKIP_REPOS"
for r in "${_skip[@]}"; do
  r="${r// /}"
  [[ -n "$r" ]] && SKIP_REPO_MAP["$r"]=1
done

IFS=',' read -r -a _pkgs <<< "$INCLUDE_PACKAGES"
for p in "${_pkgs[@]}"; do
  p="${p// /}"
  [[ -n "$p" ]] && WANT_PKG["$p"]=1
done

IFS=',' read -r -a _coords <<< "$INCLUDE_COORDS"
for c in "${_coords[@]}"; do
  c="${c// /}"
  [[ -n "$c" ]] && WANT_COORD["$c"]=1
done

IFS=',' read -r -a _exts <<< "$PREFERRED_EXTS"
for e in "${_exts[@]}"; do
  e="${e// /}"
  [[ -n "$e" ]] && OKEXT["$e"]=1
done

###############################################
# Artifactory API endpoints
###############################################
API_REPOS="${ARTIFACTORY_BASE_URL}/artifactory/api/repositories"
API_LATEST="${ARTIFACTORY_BASE_URL}/artifactory/api/search/latestVersion"
API_AQL="${ARTIFACTORY_BASE_URL}/artifactory/api/search/aql"

###############################################
# Repo discovery
###############################################
get_maven_repos() {
  # If INCLUDE_REPOS is explicitly set, trust it and skip API discovery.
  if [[ -n "${INCLUDE_REPOS:-}" ]]; then
    tr ',' '\n' <<< "$INCLUDE_REPOS" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | awk 'NF'
    return 0
  fi

  # Fallback: discover from Artifactory API
  curl_json "$API_REPOS" | jq -r '
    .[]
    | select(
        ((.packageType? // "" | ascii_downcase) == "maven")
        or ((.key? // "") | test("maven|snapshot|plugin"; "i"))
      )
    | .key
  ' | sort -u
}

###############################################
# Coordinate discovery
###############################################
discover_coords_aql() {
  local group_slash="${NAMESPACE_PREFIX//./\/}"
  local q
  q=$(cat <<AQL
items.find({
  "path": {"\$match":"${group_slash}*"},
  "\$or": [
    {"name":{"\$match":"*.ear"}},
    {"name":{"\$match":"*.war"}}
  ]
}).include("repo","path","name").limit(${DISCOVERY_LIMIT})
AQL
)

  curl -fsSL \
    --retry 4 --retry-delay 2 \
    -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
    -H "Content-Type: text/plain" \
    --data-binary "$q" \
    "$API_AQL" \
  | jq -r '.results[]? | "\(.repo)|\(.path)|\(.name)"' \
  | awk -F'|' '
      {
        path=$2
        n=split(path, parts, "/")
        if (n < 2) next
        artifact=parts[n-1]
        gp=""
        for (i=1;i<=n-2;i++) gp = gp (i==1 ? parts[i] : "." parts[i])
        if (artifact != "" && gp != "") print gp ":" artifact
      }
    ' \
  | sort -u
}

###############################################
# Version resolution
###############################################
latest_version_in_repo() {
  local repo="$1" group="$2" artifact="$3"
  local url="${API_LATEST}?g=${group}&a=${artifact}&repos=${repo}"
  local v

  v="$(curl -fsSL \
      --retry 4 --retry-delay 2 \
      -u "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" \
      "$url" 2>/dev/null || true)"

  [[ -n "$v" ]] || return 1

  if [[ -n "$VERSION_REGEX" ]] && ! printf '%s' "$v" | grep -Eq "$VERSION_REGEX"; then
    return 1
  fi

  printf '%s' "$v"
}

###############################################
# Snapshot filename resolution
###############################################
snapshot_candidates() {
  local repo="$1" group="$2" artifact="$3" ver="$4"
  local group_path="${group//./\/}"
  local meta="${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/${ver}/maven-metadata.xml"
  local xml

  xml="$(curl_xml "$meta" 2>/dev/null || true)"
  [[ -n "$xml" ]] || return 0

  awk '
    /<snapshotVersion>/ { in_block=1; val=""; ext="" }
    in_block && /<value>/     { gsub(/.*<value>|<\/value>.*/, "", $0); val=$0 }
    in_block && /<extension>/ { gsub(/.*<extension>|<\/extension>.*/, "", $0); ext=$0 }
    in_block && /<\/snapshotVersion>/ {
      if (val != "" && ext != "") print val "|" ext
      in_block=0; val=""; ext=""
    }
  ' <<< "$xml" | while IFS='|' read -r val ext; do
    [[ -n "${OKEXT[$ext]+x}" ]] && echo "${artifact}-${val}.${ext}"
  done

  local ts bn
  ts="$(sed -n 's/.*<timestamp>\(.*\)<\/timestamp>.*/\1/p' <<< "$xml" | head -n1)"
  bn="$(sed -n 's/.*<buildNumber>\(.*\)<\/buildNumber>.*/\1/p' <<< "$xml" | head -n1)"

  if [[ -n "$ts" && -n "$bn" ]]; then
    for e in "${!OKEXT[@]}"; do
      echo "${artifact}-${ver%-SNAPSHOT}-${ts}-${bn}.${e}"
    done
  fi
}

###############################################
# File candidates
###############################################
build_candidate_filenames() {
  local artifact="$1" ver="$2"
  local -a names=()

  if [[ "$ver" == *-SNAPSHOT ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] && names+=( "$f" )
    done
  else
    if [[ "$artifact" == *-war ]]; then
      names+=( "${artifact}-${ver}.war" )
    fi
    if [[ "$artifact" == *-ear ]]; then
      names+=( "${artifact}-${ver}.ear" )
    fi
    if ((${#names[@]} == 0)); then
      for e in "${!OKEXT[@]}"; do
        names+=( "${artifact}-${ver}.${e}" )
      done
    fi
  fi

  printf '%s\n' "${names[@]}"
}

###############################################
# Main
###############################################
mapfile -t ALL_REPOS < <(get_maven_repos)
[[ ${#ALL_REPOS[@]} -gt 0 ]] || die "No repos available. Set INCLUDE_REPOS or verify Artifactory API access."

log "Repos to scan: ${ALL_REPOS[*]}"

declare -A COORDS=()

if [[ ${#WANT_COORD[@]} -gt 0 ]]; then
  for c in "${!WANT_COORD[@]}"; do
    COORDS["$c"]=1
  done
  log "Using INCLUDE_COORDS list (${#COORDS[@]} coords)"
elif [[ ${#WANT_PKG[@]} -gt 0 ]]; then
  for p in "${!WANT_PKG[@]}"; do
    COORDS["${NAMESPACE_PREFIX}:${p}"]=1
  done
  log "Using INCLUDE_PACKAGES list (${#COORDS[@]} coords) under group ${NAMESPACE_PREFIX}"
else
  log "INCLUDE_PACKAGES not set; discovering via AQL..."
  while read -r c; do
    [[ -n "$c" ]] && COORDS["$c"]=1
  done < <(discover_coords_aql || true)

  [[ ${#COORDS[@]} -gt 0 ]] || die "No coords discovered via AQL. Set INCLUDE_PACKAGES for deterministic downloads."
  log "Discovered ${#COORDS[@]} coords"
fi

declare -A DOWNLOADED=()

for key in "${!COORDS[@]}"; do
  group="${key%%:*}"
  artifact="${key##*:}"

  [[ -n "${DOWNLOADED[$key]+x}" ]] && continue

  success=0
  for repo in "${ALL_REPOS[@]}"; do
    ver="$(latest_version_in_repo "$repo" "$group" "$artifact" || true)"
    [[ -n "$ver" ]] || continue

    group_path="${group//./\/}"
    base="${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/${ver}"

    filenames=()
    if [[ "$ver" == *-SNAPSHOT ]]; then
      while IFS= read -r f; do
        [[ -n "$f" ]] && filenames+=( "$f" )
      done < <(snapshot_candidates "$repo" "$group" "$artifact" "$ver")

      if ((${#filenames[@]} == 0)); then
        for e in "${!OKEXT[@]}"; do
          filenames+=( "${artifact}-${ver}.${e}" )
          filenames+=( "${artifact}-${ver%-SNAPSHOT}.${e}" )
        done
      fi
    else
      while IFS= read -r f; do
        [[ -n "$f" ]] && filenames+=( "$f" )
      done < <(build_candidate_filenames "$artifact" "$ver")
    fi

    log "Resolved version for ${group}:${artifact} in ${repo} -> ${ver}"
    log "Candidate filenames: ${filenames[*]}"

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

    if [[ -z "$got" ]]; then
      warn "[$artifact] no binary found in repo=$repo version=$ver"
      continue
    fi

    out="${DL_DIR}/$(basename "$got")"
    log "↓ ${group}:${artifact}:${ver} @ ${repo} -> $(basename "$got")"

    if curl_download "$got" "$out"; then
      DOWNLOADED["$key"]=1
      success=1
      break
    else
      err "[$artifact] download failed from repo=$repo url=$got"
      rm -f "$out" || true
    fi
  done

  if [[ $success -ne 1 ]]; then
    warn "[$artifact] unable to fetch ${group}:${artifact} from any repo"
  fi
done

log "Done. Artifacts stored in $DL_DIR"