sudo tee /app/bbmirror/bin/oneshot_mirror_all.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# ONE-TIME prod -> dev Bitbucket mirror (all projects). Reads prod, writes dev only.
set -uo pipefail

CONF="${MIRROR_CONF:-/app/bbmirror/etc/oneshot.env}"
[[ -r "$CONF" ]] || { echo "ERROR: cannot read $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"
: "${PROD_URL:?}" "${PROD_TOKEN:?}" "${DEV_URL:?}" "${DEV_TOKEN:?}"

CACHE_DIR="${CACHE_DIR:-/app/bbmirror/cache-oneshot}"
STATE_DIR="${STATE_DIR:-/app/bbmirror/run/oneshot}"
DRY_RUN="${DRY_RUN:-1}"                     # default is dry-run; DRY_RUN=0 to write
ONLY_PROJECT="${ONLY_PROJECT:-}"
ONLY_REPO="${ONLY_REPO:-}"
EXCLUDE_PROJECTS="${EXCLUDE_PROJECTS:-CNXS}" # handled by cnxs_mirror.sh
EXCLUDE_REPOS="${EXCLUDE_REPOS:-}"          # space-separated KEY/slug
INCLUDE_PERSONAL="${INCLUDE_PERSONAL:-0}"
FORCE_EXISTING="${FORCE_EXISTING:-1}"       # 1 = overwrite dev repos that already have content
FORCE_RERUN="${FORCE_RERUN:-0}"

log() { echo "$(date '+%F %T') $*"; }
die() { echo "$(date '+%F %T') ERROR: $*" >&2; exit 1; }

# Guardrails
[[ "$PROD_URL" != "$DEV_URL" ]] || die "PROD_URL and DEV_URL are identical"
[[ "$DEV_URL" != *mgmt* ]] || die "DEV_URL looks like a prod (mgmt) host: $DEV_URL"
command -v jq  >/dev/null || die "jq not found"
command -v git >/dev/null || die "git not found"
mkdir -p "$CACHE_DIR" "$STATE_DIR/created" "$STATE_DIR/done"
DONE_MARKER="$STATE_DIR/ALL_DONE"
[[ ! -e "$DONE_MARKER" || "$FORCE_RERUN" == 1 ]] || die "one-time mirror already completed ($DONE_MARKER)"
exec 9>"$STATE_DIR/lock"
flock -n 9 || { log "Another run is in progress; exiting"; exit 0; }

# --- REST helpers (token via curl config on stdin, never on argv) -----------
api() { # base token method path [json]
  local base="$1" token="$2" method="$3" path="$4" data="${5:-}"
  [[ "$base" != "$PROD_URL" || "$method" == GET ]] || die "refusing non-GET against PROD"
  local args=(-sS --fail --max-time 60 -X "$method" -H 'Accept: application/json' -K -)
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' --data "$data")
  curl "${args[@]}" "${base}${path}" <<<"header = \"Authorization: Bearer ${token}\""
}
http_code() { # base token path
  curl -sS -o /dev/null -w '%{http_code}' --max-time 60 -H 'Accept: application/json' -K - "${1}${3}" \
    <<<"header = \"Authorization: Bearer ${2}\""
}
git_with() { # token args...
  local token="$1"; shift
  GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Bearer ${token}" git "$@"
}

list_prod_repos() { # TSV: key, project name, project type, slug, repo name, state
  local start=0 resp
  while :; do
    resp="$(api "$PROD_URL" "$PROD_TOKEN" GET "/rest/api/1.0/repos?limit=100&start=${start}")" || return 1
    jq -r '.values[] | [.project.key, .project.name, .project.type, .slug, .name, .state] | @tsv' <<<"$resp"
    [[ "$(jq -r '.isLastPage' <<<"$resp")" == "true" ]] && break
    start="$(jq -r '.nextPageStart' <<<"$resp")"
  done
}

declare -A PROJ_OK
ensure_dev_project() { # key name
  local key="$1" pname="$2" code
  [[ -n "${PROJ_OK[$key]:-}" ]] && return 0
  code="$(http_code "$DEV_URL" "$DEV_TOKEN" "/rest/api/1.0/projects/${key}")"
  case "$code" in
    200) ;;
    404) log "  dev project ${key} missing; creating"
         if [[ "$DRY_RUN" != 1 ]]; then
           api "$DEV_URL" "$DEV_TOKEN" POST /rest/api/1.0/projects \
             "$(jq -n --arg k "$key" --arg n "$pname" '{key:$k,name:$n}')" >/dev/null || return 1
         fi ;;
    *)   log "  ERROR: dev project check for ${key} returned HTTP ${code}"; return 1 ;;
  esac
  PROJ_OK[$key]=1
}

dev_repo_state() { # key slug -> missing | empty | content | error
  local code resp
  code="$(http_code "$DEV_URL" "$DEV_TOKEN" "/rest/api/1.0/projects/${1}/repos/${2}")"
  case "$code" in 404) echo missing; return ;; 200) ;; *) echo error; return ;; esac
  resp="$(api "$DEV_URL" "$DEV_TOKEN" GET "/rest/api/1.0/projects/${1}/repos/${2}/branches?limit=1")" || { echo error; return; }
  [[ "$(jq -r '.size' <<<"$resp")" == "0" ]] && echo empty || echo content
}

sync_default_branch() { # key slug (best-effort)
  local p d
  p="$(api "$PROD_URL" "$PROD_TOKEN" GET "/rest/api/1.0/projects/${1}/repos/${2}/branches/default" 2>/dev/null | jq -r '.id // empty')" || return 0
  d="$(api "$DEV_URL" "$DEV_TOKEN" GET "/rest/api/1.0/projects/${1}/repos/${2}/branches/default" 2>/dev/null | jq -r '.id // empty')" || true
  [[ -n "$p" && "$p" != "$d" ]] || return 0
  api "$DEV_URL" "$DEV_TOKEN" PUT "/rest/api/1.0/projects/${1}/repos/${2}/branches/default" \
    "$(jq -n --arg id "$p" '{id:$id}')" >/dev/null 2>&1 && log "  default branch -> $p" || log "  WARN: could not set default branch (non-fatal)"
}

SKIP_EXISTING_N=0
mirror_repo() { # key pname slug name
  local key="$1" pname="$2" slug="$3" name="$4" id="${1}__${3}" st created
  local lk="${key,,}" gd="${CACHE_DIR}/${1}__${3}.git"
  local prod_git="${PROD_URL}/scm/${lk}/${slug}.git" dev_git="${DEV_URL}/scm/${lk}/${slug}.git"

  [[ -e "$STATE_DIR/done/$id" ]] && { log "  already mirrored by this one-time run; skipping"; return 0; }
  ensure_dev_project "$key" "$pname" || return 1
  st="$(dev_repo_state "$key" "$slug")"
  case "$st" in
    missing) log "  dev repo missing; will create" ;;
    empty)   log "  dev repo exists but is empty; will populate" ;;
    content) if [[ -e "$STATE_DIR/created/$id" || "$FORCE_EXISTING" == 1 ]]; then
               log "  resuming/overwriting (created by this run, or FORCE_EXISTING=1)"
             else
               log "  dev repo already has content; leaving untouched"
               SKIP_EXISTING_N=$((SKIP_EXISTING_N+1)); return 0
             fi ;;
    *) log "  ERROR: cannot determine dev repo state"; return 1 ;;
  esac
  [[ "$DRY_RUN" == 1 ]] && { log "  [dry-run] would mirror ${prod_git} -> ${dev_git}"; return 0; }

  if [[ "$st" == missing ]]; then
    created="$(api "$DEV_URL" "$DEV_TOKEN" POST "/rest/api/1.0/projects/${key}/repos" \
      "$(jq -n --arg n "$name" '{name:$n,scmId:"git",forkable:false}')")" || return 1
    [[ "$(jq -r '.slug' <<<"$created")" == "$slug" ]] \
      || { log "  ERROR: dev slug '$(jq -r '.slug' <<<"$created")' != prod slug '$slug'"; return 1; }
    touch "$STATE_DIR/created/$id"
  fi

  [[ -d "$gd" ]] || git init --bare -q "$gd" || return 1
  git --git-dir="$gd" remote remove prod >/dev/null 2>&1 || true
  git --git-dir="$gd" remote add prod "$prod_git" || return 1
  git --git-dir="$gd" remote set-url --push prod "DISABLED-never-push-to-prod" || return 1

  git_with "$PROD_TOKEN" --git-dir="$gd" fetch --prune -q prod \
    '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' || { log "  ERROR: fetch from prod failed"; return 1; }

  if ! git --git-dir="$gd" for-each-ref --count=1 refs/heads | grep -q .; then
    log "  prod repo has no branches; nothing to push"; rm -rf "$gd"; touch "$STATE_DIR/done/$id"; return 0
  fi
  if [[ "$st" != missing ]]; then
    mkdir -p "$STATE_DIR/old-refs"
    git_with "$DEV_TOKEN" ls-remote "$dev_git" > "$STATE_DIR/old-refs/${id}.txt" 2>/dev/null \
      || { log "  ERROR: could not record dev refs before overwrite; not touching this repo"; return 1; }
    if [[ "$st" == content && ! -s "$STATE_DIR/old-refs/${id}.txt" ]]; then
      log "  ERROR: dev repo reports content but ls-remote returned no refs; not touching this repo"; return 1
    fi
  fi
  # Pass 1: create/force-update everything (no deletes). Pass 2, after default-branch sync: prune dev-only refs.
  git_with "$DEV_TOKEN" --git-dir="$gd" push -q "$dev_git" \
    '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' || { log "  ERROR: push to dev failed"; return 1; }
  sync_default_branch "$key" "$slug"
  git_with "$DEV_TOKEN" --git-dir="$gd" push -q --prune "$dev_git" \
    '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' || { log "  ERROR: prune push to dev failed"; return 1; }
  rm -rf "$gd"; touch "$STATE_DIR/done/$id"
  log "  OK"
}

# ---------------------------------------------------------------------------
log "=== ONE-TIME mirror start (dry_run=${DRY_RUN}, only_project='${ONLY_PROJECT}', only_repo='${ONLY_REPO}') ==="
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
list_prod_repos > "$TMP" || die "could not list prod repos"
[[ -s "$TMP" ]] || die "prod returned zero repos; refusing to continue"
log "Prod repos visible to token: $(wc -l < "$TMP")  (compare with the UI count)"

ok=0; fail=0; skipped=0; failed_list=()
while IFS=$'\t' read -r key pname ptype slug name state; do
  [[ -n "$ONLY_PROJECT" && "${key^^}" != "${ONLY_PROJECT^^}" ]] && continue
  [[ -n "$ONLY_REPO" && "$slug" != "$ONLY_REPO" ]] && continue
  if [[ " ${EXCLUDE_PROJECTS^^} " == *" ${key^^} "* ]]; then skipped=$((skipped+1)); continue; fi
  if [[ "$ptype" == PERSONAL && "$INCLUDE_PERSONAL" != 1 ]]; then skipped=$((skipped+1)); continue; fi
  if [[ " ${EXCLUDE_REPOS} " == *" ${key}/${slug} "* ]]; then log "- ${key}/${slug}: excluded"; skipped=$((skipped+1)); continue; fi
  if [[ "$state" != "AVAILABLE" ]]; then log "- ${key}/${slug}: state=${state}; skipping"; skipped=$((skipped+1)); continue; fi
  log "- ${key}/${slug}"
  if mirror_repo "$key" "$pname" "$slug" "$name"; then ok=$((ok+1)); else fail=$((fail+1)); failed_list+=("${key}/${slug}"); fi
done < "$TMP"

log "=== done: ok=${ok} failed=${fail} skipped=${skipped} (of which dev-already-had-content=${SKIP_EXISTING_N}) ==="
if (( fail > 0 )); then log "FAILED repos: ${failed_list[*]}"; exit 1; fi
if [[ "$DRY_RUN" != 1 && -z "$ONLY_PROJECT" && -z "$ONLY_REPO" ]]; then
  touch "$DONE_MARKER"; log "Wrote $DONE_MARKER; this one-time mirror will refuse to run again."
fi
EOF
sudo chmod 700 /app/bbmirror/bin/oneshot_mirror_all.sh
sudo bash -n /app/bbmirror/bin/oneshot_mirror_all.sh && echo syntax-ok