#!/usr/bin/env bash

set -uo pipefail

CONF="${MIRROR_CONF:-/app/bbmirror/etc/mirror.env}"
[[ -r "$CONF" ]] || { echo "ERROR: cannot read $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

: "${PROD_URL:?}" "${PROD_TOKEN:?}" "${DEV_URL:?}" "${DEV_TOKEN:?}"
PROJECT_KEY="${PROJECT_KEY:-CNXS}"
CACHE_DIR="${CACHE_DIR:-/app/bbmirror/cache}"
LOCK_FILE="${LOCK_FILE:-/app/bbmirror/run/cnxs_mirror.lock}"
DRY_RUN="${DRY_RUN:-0}"
ONLY_REPO="${ONLY_REPO:-}"
# Space-separated repo slugs that are never touched (neither created nor synced).
# These stay writable/independent in dev (e.g. release start/finish testing).
EXCLUDE_REPOS="${EXCLUDE_REPOS:-releasetest}"

log() { echo "$(date '+%F %T') $*"; }
die() { log "ERROR: $*"; exit 1; }

# Guardrails
[[ "$PROD_URL" != "$DEV_URL" ]] || die "PROD_URL and DEV_URL are identical; refusing to run"
command -v jq  >/dev/null || die "jq not found"
command -v git >/dev/null || die "git not found"
mkdir -p "$CACHE_DIR/$PROJECT_KEY" "$(dirname "$LOCK_FILE")"

# Rerun/overlap safety: one run at a time
exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another run is in progress; exiting"; exit 0; }

# --- REST helpers (token passed via curl config on a pipe, not on argv) ----
api() { # base token method path [json]
  # Auth header goes to curl via stdin config (-K -), so the token is never on argv.
  # (A process substitution stored in an array does NOT survive: bash closes it
  # after the assignment, before curl runs.)
  local base="$1" token="$2" method="$3" path="$4" data="${5:-}"
  local args=(-sS --fail --max-time 60 -X "$method" -H 'Accept: application/json' -K -)
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' --data "$data")
  curl "${args[@]}" "${base}${path}" <<<"header = \"Authorization: Bearer ${token}\""
}
http_code() { # base token path
  curl -sS -o /dev/null -w '%{http_code}' --max-time 60 \
    -H 'Accept: application/json' -K - "${1}${3}" \
    <<<"header = \"Authorization: Bearer ${2}\""
}

# --- git helpers (token via env, not in URL or argv) ------------------------
git_with() { # token args...
  local token="$1"; shift
  GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Bearer ${token}" git "$@"
}

list_prod_repos() {
  local start=0 resp
  while :; do
    resp="$(api "$PROD_URL" "$PROD_TOKEN" GET \
      "/rest/api/1.0/projects/${PROJECT_KEY}/repos?limit=100&start=${start}")" || return 1
    jq -r '.values[] | [.slug, .name, .state] | @tsv' <<<"$resp"
    [[ "$(jq -r '.isLastPage' <<<"$resp")" == "true" ]] && break
    start="$(jq -r '.nextPageStart' <<<"$resp")"
  done
}

ensure_dev_project() {
  local code
  code="$(http_code "$DEV_URL" "$DEV_TOKEN" "/rest/api/1.0/projects/${PROJECT_KEY}")"
  case "$code" in
    200) return 0 ;;
    404) log "Dev project ${PROJECT_KEY} missing; creating"
         [[ "$DRY_RUN" == 1 ]] && return 0
         api "$DEV_URL" "$DEV_TOKEN" POST /rest/api/1.0/projects \
           "$(jq -n --arg k "$PROJECT_KEY" '{key:$k,name:$k}')" >/dev/null ;;
    *)   die "Dev project check returned HTTP $code (auth/URL problem?)" ;;
  esac
}

ensure_dev_repo() { # slug name
  local slug="$1" name="$2" code created
  code="$(http_code "$DEV_URL" "$DEV_TOKEN" "/rest/api/1.0/projects/${PROJECT_KEY}/repos/${slug}")"
  case "$code" in
    200) return 0 ;;
    404) log "  dev repo ${slug} missing; creating"
         [[ "$DRY_RUN" == 1 ]] && return 0
         created="$(api "$DEV_URL" "$DEV_TOKEN" POST \
           "/rest/api/1.0/projects/${PROJECT_KEY}/repos" \
           "$(jq -n --arg n "$name" '{name:$n,scmId:"git",forkable:false}')")" || return 1
         # Slug must match prod's, since it is derived from the name
         [[ "$(jq -r '.slug' <<<"$created")" == "$slug" ]] \
           || { log "  ERROR: dev slug '$(jq -r '.slug' <<<"$created")' != prod slug '$slug'"; return 1; } ;;
    *)   log "  ERROR: dev repo check for ${slug} returned HTTP $code"; return 1 ;;
  esac
}

sync_default_branch() { # slug  (best-effort, non-fatal)
  local slug="$1" p d
  p="$(api "$PROD_URL" "$PROD_TOKEN" GET "/rest/api/1.0/projects/${PROJECT_KEY}/repos/${slug}/branches/default" 2>/dev/null | jq -r '.id // empty')" || return 0
  d="$(api "$DEV_URL"  "$DEV_TOKEN"  GET "/rest/api/1.0/projects/${PROJECT_KEY}/repos/${slug}/branches/default" 2>/dev/null | jq -r '.id // empty')" || true
  [[ -n "$p" && "$p" != "$d" ]] || return 0
  log "  default branch: dev '${d:-none}' -> '$p'"
  api "$DEV_URL" "$DEV_TOKEN" PUT "/rest/api/1.0/projects/${PROJECT_KEY}/repos/${slug}/branches/default" \
    "$(jq -n --arg id "$p" '{id:$id}')" >/dev/null 2>&1 || log "  WARN: could not set default branch (non-fatal)"
}

mirror_repo() { # slug name
  local slug="$1" name="$2"
  local gd="${CACHE_DIR}/${PROJECT_KEY}/${slug}.git"
  local lk="${PROJECT_KEY,,}"
  local prod_git="${PROD_URL}/scm/${lk}/${slug}.git"
  local dev_git="${DEV_URL}/scm/${lk}/${slug}.git"

  ensure_dev_repo "$slug" "$name" || return 1
  [[ "$DRY_RUN" == 1 ]] && { log "  [dry-run] would fetch ${prod_git} and push to ${dev_git}"; return 0; }

  [[ -d "$gd" ]] || git init --bare -q "$gd" || return 1
  git --git-dir="$gd" remote remove prod >/dev/null 2>&1 || true
  git --git-dir="$gd" remote add prod "$prod_git" || return 1
  git --git-dir="$gd" remote set-url --push prod "DISABLED-never-push-to-prod" || return 1

  # Read from prod. Explicit refspecs only (avoids Bitbucket hidden PR refs).
  git_with "$PROD_TOKEN" --git-dir="$gd" fetch --prune -q prod \
    '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' || { log "  ERROR: fetch from prod failed"; return 1; }

  # Safety: never prune dev down to nothing because of an empty fetch
  if ! git --git-dir="$gd" for-each-ref --count=1 refs/heads | grep -q .; then
    log "  prod repo has no branches; skipping push"; return 0
  fi

  # Write to dev only. Force + prune so dev == prod.
  git_with "$DEV_TOKEN" --git-dir="$gd" push --prune -q "$dev_git" \
    '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' || { log "  ERROR: push to dev failed"; return 1; }

  sync_default_branch "$slug"
  log "  OK"
}

# ---------------------------------------------------------------------------
log "=== CNXS mirror start (project=${PROJECT_KEY}, dry_run=${DRY_RUN}) ==="
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
list_prod_repos > "$TMP" || die "could not list prod repos"
[[ -s "$TMP" ]] || die "prod returned zero repos; refusing to continue"
log "Prod repos: $(wc -l < "$TMP")"

ensure_dev_project

ok=0; fail=0; skipped=0; failed_list=()
while IFS=$'\t' read -r slug name state; do
  [[ -n "$ONLY_REPO" && "$slug" != "$ONLY_REPO" ]] && continue
  if [[ " ${EXCLUDE_REPOS} " == *" ${slug} "* ]]; then
    log "- ${slug}: excluded; leaving dev copy untouched"; skipped=$((skipped+1)); continue
  fi
  if [[ "$state" != "AVAILABLE" ]]; then
    log "- ${slug}: state=${state}; skipping"; skipped=$((skipped+1)); continue
  fi
  log "- ${slug}"
  if mirror_repo "$slug" "$name"; then ok=$((ok+1)); else fail=$((fail+1)); failed_list+=("$slug"); fi
done < "$TMP"

log "=== done: ok=${ok} failed=${fail} skipped=${skipped} ==="
(( fail == 0 )) || { log "FAILED repos: ${failed_list[*]}"; exit 1; }