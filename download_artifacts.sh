#!/usr/bin/env bash
# Download latest EAR/WAR artifacts for gov.gsa.cnxs.* from Artifactory Maven repos,
# with robust SNAPSHOT resolution, explicit binary filtering, and repo failover.

set -euo pipefail
[[ "${DEBUG:-}" == "1" ]] && set -x

###############################################
# Defaults (override via env)
###############################################
ARTIFACTORY_BASE_URL="${ARTIFACTORY_BASE_URL:-https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov}"
ARTIFACTORY_USER="${ARTIFACTORY_USER:-sa_bamboo}"

# Prefer a Bamboo secret var or explicit env var.
# IMPORTANT: do not echo this value anywhere.
_xtrace_on=0
[[ $- == *x* ]] && _xtrace_on=1 && set +x
ARTIFACTORY_TOKEN="${ARTIFACTORY_TOKEN:-${bamboo_artifactory_access_token_secret:-}}"
(( _xtrace_on )) && set -x

DL_DIR="${DL_DIR:-./artifacts}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-gov.gsa.cnxs}"   # groupId prefix (dot form)
VERSION_REGEX="${VERSION_REGEX:-}"                     # e.g. "(RC|SNAPSHOT)"
INCLUDE_REPOS="${INCLUDE_REPOS:-}"                     # "repo1,repo2"
SKIP_REPOS="${SKIP_REPOS:-}"                           # "repo3,repo4"
INCLUDE_PACKAGES="${INCLUDE_PACKAGES:-}"               # "task-ear,ws-services-ear,..." (optional)
PREFERRED_EXTS="${PREFERRED_EXTS:-ear,war}"            # only accept these extensions
DISCOVERY_LIMIT="${DISCOVERY_LIMIT:-5000}"             # AQL discovery cap

###############################################
# Requirements
###############################################
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need jq; need curl; need awk; need sed

mkdir -p "$DL_DIR"

log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn(){ printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err(){ printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

die(){ err "$*"; exit 1; }

[[ -n "${ARTIFACTORY_TOKEN}" ]] || die "ARTIFACTORY_TOKEN is empty. Set bamboo_artifactory_access_token_secret (or ARTIFACTORY_TOKEN)."

log "Using ARTIFACTORY_BASE_URL=$ARTIFACTORY_BASE_URL as user=$ARTIFACTORY_USER"
log "DL_DIR=$DL_DIR NAMESPACE_PREFIX=$NAMESPACE_PREFIX VERSION_REGEX=${VERSION_REGEX:-<none>} PREFERRED_EXTS=$PREFERRED_EXTS"
[[ -n "$INCLUDE_REPOS" ]] && log "INCLUDE_REPOS=$INCLUDE_REPOS"
[[ -n "$SKIP_REPOS" ]] && log "SKIP_REPOS=$SKIP_REPOS"
[[ -n "$INCLUDE_PACKAGES" ]] && log "INCLUDE_PACKAGES=$INCLUDE_PACKAGES"

###############################################
# Auth helpers (avoid token echo)
###############################################
curl_auth_args() {
  # Uses basic auth (works with your sa_bamboo + token setup)
  # If later you switch to Bearer token-only, we can swap this.
  printf '%s\0' "-u" "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}"
}

curl_json() {
  local url="$1"
  # shellcheck disable=SC2059
  local args; args="$(curl_auth_args)"
  curl -fsSL --retry 4 --retry-delay 2 "${args%%$'\0'*}" "${args#*$'\0'}" -H 'Accept: application/json' "$url"
}

curl_head_ok() {
  local url="$1"
  local args; args="$(curl_auth_args)"
  curl -fsI "${args%%$'\0'*}" "${args#*$'\0'}" "$url" >/dev/null 2>&1
}

curl_get() {
  local url="$1"
  local args; args="$(curl_auth_args)"
  curl -fSL --retry 5 --retry-delay 2 "${args%%$'\0'*}" "${args#*$'\0'}" "$url"
}

###############################################
# Build allow/deny sets
###############################################
declare -A ALLOW_REPO=() SKIP_REPO=() WANT_PKG=() OKEXT=()

IFS=',' read -r -a _allow <<< "${INCLUDE_REPOS}"
for r in "${_allow[@]}"; do [[ -n "$r" ]] && ALLOW_REPO["${r// /}"]=1; done

IFS=',' read -r -a _skip <<< "${SKIP_REPOS}"
for r in "${_skip[@]}"; do [[ -n "$r" ]] && SKIP_REPO["${r// /}"]=1; done

IFS=',' read -r -a _pkgs <<< "${INCLUDE_PACKAGES}"
for p in "${_pkgs[@]}"; do [[ -n "$p" ]] && WANT_PKG["${p// /}"]=1; done

IFS=',' read -r -a _exts <<< "${PREFERRED_EXTS}"
for e in "${_exts[@]}"; do e="${e// /}"; [[ -n "$e" ]] && OKEXT["$e"]=1; done

###############################################
# Artifactory API endpoints
###############################################
API_REPOS="${ARTIFACTORY_BASE_URL}/artifactory/api/repositories"
API_LATEST="${ARTIFACTORY_BASE_URL}/artifactory/api/search/latestVersion"
API_AQL="${ARTIFACTORY_BASE_URL}/artifactory/api/search/aql"

###############################################
# Repo discovery
###############################################
# Returns repo keys of Maven repos. We keep local/virtual/remote because virtuals can be useful.
get_maven_repos() {
  # /api/repositories returns a JSON array with {key,type,url,packageType,rclass,...} (fields vary)
  # Some Artifactory versions omit packageType for certain repo types; we filter by "packageType":"maven" where present,
  # and also accept virtual repos that expose "repositories":[...].
  curl_json "$API_REPOS" | jq -r '
    .[]
    | select(
        ((.packageType? // "") == "maven")
        or (.type? == "virtual" and (.repositories? != null))
      )
    | .key
  ' | sort -u
}

###############################################
# Package discovery
###############################################
# In CodeArtifact you could list packages. In Artifactory we either:
#  A) use INCLUDE_PACKAGES (fast, preferred), OR
#  B) discover by searching for *.ear/*.war under the group prefix via AQL (can be heavier)
#
# Output lines: groupId:artifactId
discover_coords_aql() {
  local group_slash="${NAMESPACE_PREFIX//./\/}"

  # Find artifacts in Maven-like paths: <group>/<artifact>/<version>/<artifact>-<version>.<ext>
  # AQL query: search by path prefix and file extension
  # NOTE: AQL endpoint returns plain text; we request fields and parse as JSON.
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

  local args; args="$(curl_auth_args)"
  curl -fsSL "${args%%$'\0'*}" "${args#*$'\0'}" \
    -H "Content-Type: text/plain" \
    --data-binary "$q" \
    "$API_AQL" \
  | jq -r '
      .results[]? | "\(.repo)|\(.path)|\(.name)"
    ' \
  | awk -F'|' '
      # path expected: group/path/.../<artifact>/<version>
      {
        repo=$1; path=$2; name=$3;
        n=split(path, parts, "/");
        if (n < 2) next;
        artifact=parts[n-1];
        version=parts[n];
        # reconstruct group path up to artifact
        gp="";
        for (i=1;i<=n-2;i++){ gp = gp (i==1?parts[i]:"/"parts[i]); }
        gsub("/", ".", gp);
        if (artifact != "" && gp != "") print gp ":" artifact;
      }
    ' \
  | sort -u
}

###############################################
# Version resolution
###############################################
latest_version_in_repo() {
  # Uses Artifactory latestVersion API:
  #   /api/search/latestVersion?g=<groupId>&a=<artifactId>&repos=<repo>[&v=<base>]
  #
  # If VERSION_REGEX is set, we pull a "best effort" by:
  #   - asking for latestVersion (no regex)
  #   - if it doesn't match regex and regex includes SNAPSHOT, we may still proceed for snapshots
  # Real regex filtering across all versions would require a deeper search; this keeps it lightweight.
  local repo="$1" group="$2" artifact="$3"

  local url="${API_LATEST}?g=${group}&a=${artifact}&repos=${repo}"
  local v; v="$(curl_get "$url" 2>/dev/null || true)"
  [[ -z "$v" ]] && return 1

  if [[ -n "$VERSION_REGEX" ]]; then
    if ! printf '%s' "$v" | grep -Eq "$VERSION_REGEX"; then
      # Not a match -> return empty (forces failover to next repo)
      return 1
    fi
  fi
  printf '%s' "$v"
}

###############################################
# Snapshot resolution
###############################################
snapshot_candidates() {
  # Emits filenames within <repo>/<group>/<artifact>/<version>/ based on maven-metadata.xml snapshotVersion entries
  local repo="$1" group="$2" artifact="$3" ver="$4"

  local group_path="${group//./\/}"
  local meta="${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/${ver}/maven-metadata.xml"
  local xml; xml="$(curl_get "$meta" 2>/dev/null || true)"
  [[ -z "$xml" ]] && return 0

  # Prefer explicit snapshotVersion entries for ear/war
  awk -v A="$artifact" '
    /<snapshotVersion>/ {sb=1; val=""; ext=""}
    sb && /<value>/     {gsub(/.*<value>|<\/value>.*/,""); val=$0}
    sb && /<extension>/ {gsub(/.*<extension>|<\/extension>.*/,""); ext=$0}
    sb && /<\/snapshotVersion>/ {
      if (val != "" && ext != "") print val "|" ext;
      sb=0; val=""; ext="";
    }
  ' <<< "$xml" \
  | while IFS='|' read -r val ext; do
      [[ -n "${OKEXT[$ext]+_}" ]] && echo "${artifact}-${val}.${ext}"
    done

  # Fallback using timestamp/buildNumber if snapshotVersion blocks are missing
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
# Download helper
###############################################
download_one() {
  local url="$1" out="$2"
  if curl_get "$url" -o "$out" >/dev/null; then
    return 0
  fi
  return 1
}

###############################################
# Main flow
###############################################
mapfile -t REPOS < <(get_maven_repos)

# Apply include/skip lists
FILTERED_REPOS=()
for r in "${REPOS[@]}"; do
  [[ ${#ALLOW_REPO[@]} -gt 0 && -z "${ALLOW_REPO[$r]+_}" ]] && continue
  [[ -n "${SKIP_REPO[$r]+_}" ]] && { log "Skip repo (requested): $r"; continue; }
  FILTERED_REPOS+=( "$r" )
done

[[ ${#FILTERED_REPOS[@]} -gt 0 ]] || die "No Maven repos found after filtering."

log "Repos to scan: ${#FILTERED_REPOS[@]}"

# Determine coordinates to fetch
declare -A COORDS=()

if [[ ${#WANT_PKG[@]} -gt 0 ]]; then
  # If packages provided, we need groupId(s). Assume NAMESPACE_PREFIX as group prefix
  # You can extend this later if your artifactIds span multiple groups.
  for p in "${!WANT_PKG[@]}"; do
    COORDS["${NAMESPACE_PREFIX}:${p}"]=1
  done
  log "Using INCLUDE_PACKAGES list (${#COORDS[@]} coords) under group prefix ${NAMESPACE_PREFIX}"
else
  log "INCLUDE_PACKAGES not set -> discovering coords via AQL (limit=${DISCOVERY_LIMIT})..."
  while read -r c; do
    [[ -n "$c" ]] && COORDS["$c"]=1
  done < <(discover_coords_aql || true)

  [[ ${#COORDS[@]} -gt 0 ]] || die "No coords discovered via AQL. Set INCLUDE_PACKAGES to make this deterministic."
  log "Discovered ${#COORDS[@]} coords via AQL"
fi

# Download with repo failover per coord
declare -A DOWNLOADED=()

for key in "${!COORDS[@]}"; do
  group="${key%%:*}"
  artifact="${key##*:}"

  # If INCLUDE_PACKAGES is set, enforce it strictly
  if [[ ${#WANT_PKG[@]} -gt 0 && -z "${WANT_PKG[$artifact]+_}" ]]; then
    continue
  fi

  [[ -n "${DOWNLOADED[$key]+_}" ]] && continue

  success=0
  for repo in "${FILTERED_REPOS[@]}"; do
    ver="$(latest_version_in_repo "$repo" "$group" "$artifact" || true)"
    [[ -z "$ver" ]] && continue

    group_path="${group//./\/}"
    base="${ARTIFACTORY_BASE_URL}/artifactory/${repo}/${group_path}/${artifact}/${ver}"

    filenames=()
    if [[ "$ver" == *-SNAPSHOT ]]; then
      while IFS= read -r f; do [[ -n "$f" ]] && filenames+=( "$f" ); done < <(snapshot_candidates "$repo" "$group" "$artifact" "$ver")
      if ((${#filenames[@]}==0)); then
        # fallback guesses
        for e in "${!OKEXT[@]}"; do filenames+=( "${artifact}-${ver%-SNAPSHOT}.${e}" ); done
      fi
    else
      # releases
      if [[ "$artifact" == *"-war" ]]; then filenames+=( "${artifact}-${ver}.war" ); fi
      if [[ "$artifact" == *"-ear" ]]; then filenames+=( "${artifact}-${ver}.ear" ); fi
      if ((${#filenames[@]}==0)); then
        for e in "${!OKEXT[@]}"; do filenames+=( "${artifact}-${ver}.${e}" ); done
      fi
    fi

    got=""
    for f in "${filenames[@]}"; do
      ext="${f##*.}"
      [[ -z "${OKEXT[$ext]+_}" ]] && continue
      url="${base}/${f}"
      if curl_head_ok "$url"; then
        got="$url"
        break
      fi
    done

    if [[ -z "$got" ]]; then
      warn "[$artifact] No binary in repo=$repo ver=$ver (tried: ${filenames[*]})"
      continue
    fi

    out="${DL_DIR}/$(basename "$got")"
    log "↓ ${group}:${artifact}:${ver} @ ${repo} -> $(basename "$got")"
    if curl -fSL --retry 5 --retry-delay 2 "$(curl_auth_args | tr '\0' ' ')" -o "$out" "$got"; then
      DOWNLOADED["$key"]=1
      success=1
      break
    else
      err "[$artifact] Download failed from repo=$repo: $got"
      rm -f "$out" || true
    fi
  done

  if [[ $success -ne 1 ]]; then
    warn "[$artifact] Unable to fetch from any repo for ${group}:${artifact}"
  fi
done

log "Done. Artifacts in $DL_DIR"