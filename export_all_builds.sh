#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG =====
HOST="conexus-bamboo.edc.ds1.usda.gov"   # no protocol; add :8085 or /bamboo only if you see it in the browser URL
TOKEN="PASTE_YOUR_PAT"
# ==================

DATE="$(date +%F)"
ROOT="$HOME/bamboo-export-${DATE}"
BUILDS="$ROOT/bamboo-specs/builds"
DEPLOYS="$ROOT/bamboo-specs/deployments"
ERRORS="$ROOT/errors"
LEGACY="$ROOT/legacy-xml"
TMP="$ROOT/tmp"
LOG="$ROOT/export.log"

mkdir -p "$BUILDS" "$DEPLOYS" "$ERRORS" "$LEGACY" "$TMP"
cd "$ROOT"

log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# --- helpers ---------------------------------------------------------------

curl_json() { # url outfile -> echoes "code ctype"
  local url="$1" out="$2"
  local outdir; outdir="$(dirname "$out")"; mkdir -p "$outdir"
  local line
  line="$(curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
              -o "$out" -w '%{http_code} %{content_type}' "$url" || true)"
  # shellcheck disable=SC2086
  echo $line
}

curl_yaml() { # url outfile -> 0 if YAML written, 1 otherwise (moves body to errors/)
  local url="$1" out="$2"
  local tmp="$TMP/$(basename "$out").tmp"
  local line code ctype base
  line="$(curl -sS -H "Authorization: Bearer $TOKEN" -H "Accept: text/x-yaml, */*" \
              -o "$tmp" -w '%{http_code} %{content_type}' "$url" || true)"
  read -r code ctype <<<"$line"
  base="$(basename "$out" .yaml)"

  # Treat anything that starts with XML as an error body
  if [[ "$code" == "200" ]] && head -n1 "$tmp" | grep -qv '^<\?xml'; then
    mv "$tmp" "$out"
    return 0
  else
    mv "$tmp" "$ERRORS/${base}.body" 2>/dev/null || true
    printf '%s %s\n%s\n' "$code" "$ctype" "$url" > "$ERRORS/${base}.http"
    return 1
  fi
}

# --- 1) Collect ALL plan keys (with pagination) ----------------------------

BATCH=200
start=0
> "$TMP/plan_keys_raw.txt"

log "Collecting ALL plan keys (with pagination)…"
while : ; do
  page="$TMP/plans_${start}.json"
  read -r code ctype <<<"$(curl_json "https://${HOST}/rest/api/latest/plan?max-results=${BATCH}&start-index=${start}" "$page")"

  if [[ "$code" != "200" || "$ctype" != application/json* ]]; then
    log "ERROR page start=${start} → HTTP $code $ctype (body saved to errors/)"
    cp -f "$page" "$ERRORS/plans_page_${start}.body" 2>/dev/null || true
    break
  fi

  # append keys from this page
  jq -r '.plans.plan[]?.key' "$page" >> "$TMP/plan_keys_raw.txt" || true

  # continue until this page returned < BATCH items
  got="$(jq '.plans.plan | length' "$page")"
  log "  page start=${start} got=${got}"
  (( got < BATCH )) && break
  start=$(( start + BATCH ))
done

# de-dup and persist the list
awk 'NF && !seen[$0]++' "$TMP/plan_keys_raw.txt" > "$ROOT/plan_keys.txt"
TOTAL_PLANS="$(wc -l < "$ROOT/plan_keys.txt" | tr -d ' ')"
log "Total plans discovered: ${TOTAL_PLANS}"
log "First few keys: $(head -n 10 "$ROOT/plan_keys.txt" | tr '\n' ' ')"

# --- 2) Export plan Specs to YAML ------------------------------------------

OK=0; FAIL=0
log "Exporting plan Specs to YAML  →  $BUILDS"
while IFS= read -r PLAN; do
  [[ -z "$PLAN" ]] && continue
  out="$BUILDS/${PLAN}.yaml"
  url="https://${HOST}/rest/api/latest/plan/${PLAN}/specs?format=YAML"
  if curl_yaml "$url" "$out"; then
    ((OK++))
  else
    # Optional: also try to capture legacy XML so nothing is lost
    curl -sS -H "Authorization: Bearer $TOKEN" \
         "https://${HOST}/rest/api/latest/export/plan?planKey=${PLAN}" \
         -o "$LEGACY/${PLAN}.xml" >/dev/null 2>&1 || true
    ((FAIL++))
  fi
done < "$ROOT/plan_keys.txt"

log "Done. ${OK} YAML specs written, ${FAIL} saved to errors (non-YAML/404/etc.)."

# --- 3) Export deployment projects (YAML) ----------------------------------

log "Discovering deployment projects…"
dep_list="$TMP/deploy_projects.json"
read -r dcode dctype <<<"$(curl_json "https://${HOST}/rest/api/latest/deploy/project/all" "$dep_list")"
if [[ "$dcode" == "200" && "$dctype" == application/json* ]]; then
  mapfile -t DEP_IDS < <(jq -r '.[].id' "$dep_list")
  log "Deployment projects discovered: ${#DEP_IDS[@]}"
  DOK=0; DFAIL=0
  for id in "${DEP_IDS[@]}"; do
    curl_yaml "https://${HOST}/rest/api/latest/deploy/project/${id}/specs?format=YAML" \
              "$DEPLOYS/${id}.yaml" && ((DOK++)) || ((DFAIL++))
  done
  log "Deployments: ${DOK} YAML specs written, ${DFAIL} saved to errors."
else
  log "WARN deployments listing failed: HTTP $dcode $dctype → skipping deployment export"
fi

# --- 4) Generate bamboo.yml that points at everything ----------------------

cat > "$ROOT/bamboo.yml" <<'YML'
version: 2
specs:
  include:
    - bamboo-specs/builds/*.yaml
    - bamboo-specs/deployments/*.yaml
YML
log "Wrote bamboo.yml"

# Summary
log "Export folder: $ROOT"
log "Build specs:   $(ls -1 "$BUILDS" 2>/dev/null | wc -l) files"
log "Deploy specs:  $(ls -1 "$DEPLOYS" 2>/dev/null | wc -l) files"
log "Errors:        $(ls -1 "$ERRORS" 2>/dev/null | wc -l) entries"