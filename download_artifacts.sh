#!/usr/bin/env bash
# Download latest EAR/WAR artifacts for gov.gsa.cnxs.* from ALL Maven-format
# CodeArtifact repositories in the domain, with robust SNAPSHOT resolution,
# explicit binary filtering, and repo failover per package.

# Defaults (override via env)
REGION="${REGION:-us-east-1}"
DOMAIN="${DOMAIN:-cnxsartifact}"
OWNER="${OWNER:-339713019047}"
DL_DIR="${DL_DIR:-./artifacts}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-gov.gsa.cnxs}"
VERSION_REGEX="${VERSION_REGEX:-}"           # e.g. "(RC|SNAPSHOT)"
INCLUDE_REPOS="${INCLUDE_REPOS:-}"           # "ll-postgres,conexus-dependencies"
SKIP_REPOS="${SKIP_REPOS:-}"                 # "ll-modelchanges,conexus-rc-local"
INCLUDE_PACKAGES="${INCLUDE_PACKAGES:-}"     # "task-ear,ws-services-ear,dpa-ear,..." (optional)
PREFERRED_EXTS="${PREFERRED_EXTS:-ear,war}"  # only accept these extensions
DEBUG="${DEBUG:-}"

set -euo pipefail
[[ "$DEBUG" == "1" ]] && set -x
mkdir -p "$DL_DIR"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need aws; need jq; need curl

log(){ printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn(){ printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err(){ printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

log "Using REGION=$REGION DOMAIN=$DOMAIN OWNER=$OWNER"
[[ -n "$INCLUDE_REPOS" ]] && log "INCLUDE_REPOS=$INCLUDE_REPOS"
[[ -n "$SKIP_REPOS" ]] && log "SKIP_REPOS=$SKIP_REPOS"
[[ -n "$INCLUDE_PACKAGES" ]] && log "INCLUDE_PACKAGES=$INCLUDE_PACKAGES"
log "Namespace filter: ${NAMESPACE_PREFIX:-<none>}  Version regex: ${VERSION_REGEX:-<none>}  PREFERRED_EXTS=$PREFERRED_EXTS"

# Auth token for CodeArtifact basic auth
TOKEN="$(aws codeartifact get-authorization-token \
  --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
  --query authorizationToken --output text)"

# Build allow/deny sets
declare -A ALLOW_REPO=() SKIP_REPO=() WANT_PKG=()
IFS=',' read -r -a _allow <<< "${INCLUDE_REPOS}";  for r in "${_allow[@]}"; do [[ -n "$r" ]] && ALLOW_REPO["${r// /}"]=1; done
IFS=',' read -r -a _skip  <<< "${SKIP_REPOS}";     for r in "${_skip[@]}";  do [[ -n "$r" ]] && SKIP_REPO["${r// /}"]=1;  done
IFS=',' read -r -a _pkgs  <<< "${INCLUDE_PACKAGES}"; for p in "${_pkgs[@]}"; do [[ -n "$p" ]] && WANT_PKG["${p// /}"]=1; done

# Preferred extensions set
declare -A OKEXT=()
IFS=',' read -r -a _exts <<< "$PREFERRED_EXTS"
for e in "${_exts[@]}"; do e="${e// /}"; [[ -n "$e" ]] && OKEXT["$e"]=1; done

# Helpers
get_all_repos(){
  local nt=""; while :; do
    if [[ -n "$nt" ]]; then
      aws codeartifact list-repositories-in-domain --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" --next-token "$nt"
    else
      aws codeartifact list-repositories-in-domain --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER"
    fi | jq -r '
      .repositories[]?.name,
      (."nextToken" // empty | tostring | select(length>0) | "NT:" + .)
    ' | while read -r line; do
          if [[ "$line" =~ ^NT:(.*)$ ]]; then nt="${BASH_REMATCH[1]}"; else echo "$line"; fi
        done
    [[ -z "$nt" ]] && break
  done
}

get_maven_endpoint(){
  aws codeartifact get-repository-endpoint \
    --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
    --repository "$1" --format maven \
    --query repositoryEndpoint --output text 2>/dev/null || echo ""
}

list_repo_packages(){
  local repo="$1" nt="" out
  while :; do
    if [[ -n "$nt" ]]; then
      out="$(aws codeartifact list-packages --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
            --repository "$repo" --format maven --next-token "$nt" \
            --query '{pkgs: packages[*].{ns:namespace,pkg:package}, nt: nextToken}' --output json 2>/dev/null || echo '{"pkgs":[],"nt":""}')"
    else
      out="$(aws codeartifact list-packages --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
            --repository "$repo" --format maven \
            --query '{pkgs: packages[*].{ns:namespace,pkg:package}, nt: nextToken}' --output json 2>/dev/null || echo '{"pkgs":[],"nt":""}')"
    fi
    printf '%s' "$out" | jq -r '.pkgs[] | "\(.ns):\(.pkg)"'
    nt="$(printf '%s' "$out" | jq -r '.nt // empty')"
    [[ -z "$nt" ]] && break
  done
}

latest_version(){
  local repo="$1" ns="$2" pkg="$3"
  if [[ -n "$VERSION_REGEX" ]]; then
    aws codeartifact list-package-versions --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
      --repository "$repo" --format maven --namespace "$ns" --package "$pkg" \
      --status Published --max-results 200 --query 'versions[].version' --output text 2>/dev/null \
    | tr '\t' '\n' | grep -E "$VERSION_REGEX" | head -n1 || true
  else
    aws codeartifact list-package-versions --region "$REGION" --domain "$DOMAIN" --domain-owner "$OWNER" \
      --repository "$repo" --format maven --namespace "$ns" --package "$pkg" \
      --status Published --sort-by PUBLISHED_TIME --max-results 1 \
      --query 'versions[0].version' --output text 2>/dev/null || true
  fi
}

# Snapshot candidates filtered to preferred extensions only
snapshot_candidates(){
  local ns="$1" pkg="$2" ver="$3" endpoint="$4"
  local group="${ns//./\/}"
  local meta="${endpoint%/}/${group}/${pkg}/${ver}/maven-metadata.xml"
  local xml; xml="$(curl -fsSL -u "aws:${TOKEN}" "$meta" || true)"
  [[ -z "$xml" ]] && return 0

  # Emit only preferred extensions (ear/war by default)
  awk -v P="$pkg" '
    /<snapshotVersion>/ {sb=1; val=""; ext=""}
    sb && /<value>/     {gsub(/.*<value>|<\/value>.*/,""); val=$0}
    sb && /<extension>/ {gsub(/.*<extension>|<\/extension>.*/,""); ext=$0}
    sb && /<\/snapshotVersion>/ {
      if (val != "" && ext != "") print val "|" ext;
      sb=0; val=""; ext="";
    }
  ' <<< "$xml" \
  | while IFS='|' read -r val ext; do
      [[ -n "${OKEXT[$ext]+_}" ]] && echo "${pkg}-${val}.${ext}"
    done

  # Strict fallback using timestamp/buildNumber if no preferred snapshotVersions exist
  if ! grep -q "<snapshotVersion>" <<< "$xml"; then
    local ts bn
    ts="$(sed -n 's/.*<timestamp>\(.*\)<\/timestamp>.*/\1/p' <<< "$xml" | head -n1)"
    bn="$(sed -n 's/.*<buildNumber>\(.*\)<\/buildNumber>.*/\1/p' <<< "$xml" | head -n1)"
    if [[ -n "$ts" && -n "$bn" ]]; then
      for e in "${!OKEXT[@]}"; do
        echo "${pkg}-${ver%-SNAPSHOT}-${ts}-${bn}.${e}"
      done
    fi
  fi
}

url_exists(){ curl -fsI -u "aws:${TOKEN}" "$1" >/dev/null 2>&1; }

# ---------- Discover packages across repos ----------
mapfile -t REPOS < <(get_all_repos | sed '/^$/d')

# Collect all repo candidates for each ns:pkg as lines:
# repo|endpoint|ns|pkg|version
ALL=()
for repo in "${REPOS[@]}"; do
  [[ ${#ALLOW_REPO[@]} -gt 0 && -z "${ALLOW_REPO[$repo]+_}" ]] && continue
  [[ -n "${SKIP_REPO[$repo]+_}" ]] && { log "Skip repo (requested): $repo"; continue; }

  endpoint="$(get_maven_endpoint "$repo")"
  if [[ -z "$endpoint" || "$endpoint" == "None" ]]; then
    log "Skip $repo (no Maven endpoint)"; continue
  fi
  log "Scanning repo: $repo"

  mapfile -t coords < <(list_repo_packages "$repo" \
    | awk -F: -v pre="$NAMESPACE_PREFIX" '
        NF==2 && ($1 ~ "^"pre) && ($2 ~ /-ear|-war/) {print}')
  [[ ${#coords[@]} -eq 0 ]] && { log "  No matching EAR/WAR packages in $repo"; continue; }

  for c in "${coords[@]}"; do
    ns="${c%%:*}"; pkg="${c##*:}"

    # If INCLUDE_PACKAGES is set, only keep those
    if [[ ${#WANT_PKG[@]} -gt 0 && -z "${WANT_PKG[$pkg]+_}" ]]; then
      continue
    fi

    ver="$(latest_version "$repo" "$ns" "$pkg")"
    if [[ -z "$ver" || "$ver" == "None" ]]; then
      warn "  No version for $ns:$pkg in $repo"; continue
    fi

    ALL+=( "$repo|$endpoint|$ns|$pkg|$ver" )
  done
done

# Group by ns:pkg so we can fail over repo-by-repo
declare -A GROUP=()
for line in "${ALL[@]}"; do
  IFS='|' read -r repo endpoint ns pkg ver <<< "$line"
  key="${ns}:${pkg}"
  GROUP["$key"]+="${line}"$'\n'
done

# Sort helper: prefer newer-looking versions (simple lexical), then repo name stable
sort_candidates(){
  # shellcheck disable=SC2002
  cat | awk -F'|' '{print $0}' | sort -t'|' -k5,5r -k1,1
}

# ------------- Download phase with repo failover -------------
declare -A DOWNLOADED=()

for key in "${!GROUP[@]}"; do
  # if INCLUDE_PACKAGES is set and this key not desired, skip
  pkg="${key##*:}"
  if [[ ${#WANT_PKG[@]} -gt 0 && -z "${WANT_PKG[$pkg]+_}" ]]; then
    continue
  fi

  # Skip if already downloaded same ns:pkg (protect against dupes)
  [[ -n "${DOWNLOADED[$key]+_}" ]] && continue

  candidates="$(printf '%s' "${GROUP[$key]}" | sed '/^$/d' | sort_candidates)"
  [[ -z "$candidates" ]] && continue

  success=0
  while IFS='|' read -r repo endpoint ns pkg ver; do
    [[ -z "$repo" ]] && continue
    group_path="${ns//./\/}"
    base="${endpoint%/}/${group_path}/${pkg}/${ver}"

    filenames=()
    if [[ "$ver" == *-SNAPSHOT ]]; then
      while IFS= read -r f; do [[ -n "$f" ]] && filenames+=( "$f" ); done < <(snapshot_candidates "$ns" "$pkg" "$ver" "$endpoint")
      if ((${#filenames[@]}==0)); then
        # fall back to guessed filename(s) for preferred exts
        for e in "${!OKEXT[@]}"; do filenames+=( "${pkg}-${ver%-SNAPSHOT}.${e}" ); done
      fi
    else
      # release: default by name, but try both preferred exts to be safe
      if [[ "$pkg" == *"-war" ]]; then
        filenames+=( "${pkg}-${ver}.war" )
      elif [[ "$pkg" == *"-ear" ]]; then
        filenames+=( "${pkg}-${ver}.ear" )
      fi
      # If pattern didn't capture, still try both preferred exts
      if ((${#filenames[@]}==0)); then
        for e in "${!OKEXT[@]}"; do filenames+=( "${pkg}-${ver}.${e}" ); done
      fi
    fi

    # Only try preferred extensions; HEAD probe each
    got=""
    for f in "${filenames[@]}"; do
      # skip non-preferred just in case
      ext="${f##*.}"
      [[ -z "${OKEXT[$ext]+_}" ]] && continue
      url="${base}/${f}"
      if url_exists "$url"; then got="$url"; break; fi
    done

    if [[ -z "$got" ]]; then
      warn "  [$pkg] No binary in $repo for version $ver (tried ${filenames[*]})"
      continue
    fi

    out="${DL_DIR}/$(basename "$got")"
    log "  ↓ ${ns}:${pkg}:${ver} @ ${repo} -> $(basename "$got")"
    if curl -fSL --retry 5 --retry-delay 2 -u "aws:${TOKEN}" -o "$out" "$got"; then
      DOWNLOADED["$key"]=1
      success=1
      break
    else
      err "  [$pkg] Download failed from $repo: $got"
      rm -f "$out" || true
    fi
  done <<< "$candidates"

  if [[ $success -ne 1 ]]; then
    warn "  [$pkg] Unable to fetch a binary from any repo for ${key}"
  fi
done

log "Done. Artifacts in $DL_DIR"