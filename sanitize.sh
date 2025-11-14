#!/usr/bin/env bash
# Clean Bamboo YAML specs exported with XML wrapper
# - Strip XML wrapper (<?xml ...><specs><spec><code> ... </code></spec></specs>)
# - Remove any `other:` block (at any indent) ONLY if it contains `concurrent-build-plugin`
# - Drop ONLY `create-plan-branch` from permissions (keep `view-configuration`)
# - Skip bamboo.yml
# - Backup originals under <ROOT>/legacy-xml/<relative path>

set -euo pipefail

ROOT="${1:-.}"                 # directory that contains your spec files
BACKUP_DIR_NAME="${2:-legacy-xml}"

# Resolve absolute paths and ensure ROOT exists
ROOT_ABS="$(cd "$ROOT" && pwd -P)"
BACKUP_ABS="${ROOT_ABS}/${BACKUP_DIR_NAME}"

mkdir -p "$BACKUP_ABS"

touched=0
xml_stripped=0
other_removed=0
create_removed=0

log(){ printf '[%(%F %T)T] %s\n' -1 "$*"; }

backup_file() {
  local src="$1"
  local rel="${src#$ROOT_ABS/}"     # path relative to ROOT_ABS
  local dst="${BACKUP_ABS}/${rel}"
  mkdir -p "$(dirname "$dst")"
  [[ -e "$dst" ]] || cp -p "$src" "$dst"
}

# --- Step 1: strip XML wrapper if present ------------------------------------
strip_xml_wrapper() {
  # in -> out; returns 0 if stripped, 1 if no stripping needed
  local in="$1" out="$2"
  # Quick check: either file begins with XML or contains <code>
  if head -n1 "$in" | grep -q '^<\?xml' || grep -q '<code>' "$in"; then
    awk '
      BEGIN {emit=0}
      {
        line=$0
        if (!emit) {
          if (line ~ /<code>/) {
            sub(/.*<code>/,"",line)
            emit=1
            # could close on same line
            if (line ~ /<\/code>/) { sub(/<\/code>.*/,"",line); print line; exit }
            print line
            next
          } else {
            next
          }
        } else {
          if (line ~ /<\/code>/) { sub(/<\/code>.*/,"",line); print line; exit }
          print line
        }
      }
    ' "$in" > "$out"
    # Remove BOM or trailing XML crumbs just in case
    sed -i -e '1s/^\xEF\xBB\xBF//' -e 's#</spec></specs>##g' "$out"
    return 0
  fi
  # Not XML-wrapped; copy through
  cp -p "$in" "$out"
  return 1
}

# --- Step 2: remove `other:` block (at any indent) ONLY if it contains concurrent-build-plugin
remove_other_block_if_plugin() {
  # in -> out
  local in="$1" out="$2"
  awk '
    function indent(s) { match(s,/^[[:space:]]*/); return RLENGTH }
    BEGIN { buf=""; dropping=0; base=0; hasplugin=0 }
    {
      if (dropping) {
        if ($0 ~ /^[[:space:]]*$/) { buf = buf $0 ORS; next }
        # boundary: indent <= base -> decide to print or drop buffer; then process current line anew
        if (indent($0) <= base) {
          if (!hasplugin) { printf "%s", buf }
          buf=""; dropping=0; hasplugin=0
          # fall through to normal processing of this line
        } else {
          buf = buf $0 ORS
          if ($0 ~ /concurrent-build-plugin/) hasplugin=1
          next
        }
      }
      # not currently dropping: detect an `other:` key at any indent
      if (match($0,/^([[:space:]]*)other:[[:space:]]*$/)) {
        base = indent($0)
        buf = ""               # start buffering this block
        dropping = 1
        hasplugin = 0
        next
      }
      print
    }
    END {
      if (dropping) {
        if (!hasplugin) { printf "%s", buf }
      }
    }
  ' "$in" > "$out"
}

# --- Step 3: drop ONLY create-plan-branch, keep view-configuration ----------
drop_create_plan_branch() {
  # in -> out
  local in="$1" out="$2"
  sed -E \
    -e 's/^([[:space:]]*-\s*view-configuration)[[:space:]]+-\s*create-plan-branch([[:space:]]*)(#.*)?$/\1\2\3/' \
    -e 's/^([[:space:]]*-\s*create-plan-branch)[[:space:]]+-\s*view-configuration([[:space:]]*)(#.*)?$/- view-configuration\2\3/' \
    -e '/^[[:space:]]*-\s*create-plan-branch([[:space:]]*)(#.*)?$/d' \
    "$in" > "$out"
}

process_one() {
  local f="$1"
  local base="$(basename "$f")"
  [[ "$base" == "bamboo.yml" ]] && return 0  # skip index file

  backup_file "$f"

  local t1 t2 t3
  t1="$(mktemp)"; t2="$(mktemp)"; t3="$(mktemp)"
  trap 'rm -f "$t1" "$t2" "$t3"' RETURN

  local did_strip=1
  if strip_xml_wrapper "$f" "$t1"; then
    did_strip=0
    ((xml_stripped++))
  fi

  remove_other_block_if_plugin "$t1" "$t2"
  drop_create_plan_branch "$t2" "$t3"

  # Write back only if changed
  if ! cmp -s "$f" "$t3"; then
    mv "$t3" "$f"
    ((touched++))
  else
    rm -f "$t3"
  fi

  # counters (did `other:` removal actually change anything?)
  if ! cmp -s "$t1" "$t2"; then ((other_removed++)); fi
  if ! cmp -s "$t2" "$f";  then ((create_removed++)); fi
}

main() {
  log "Sanitizing specs under: $ROOT_ABS"
  log "Backups will go under:  $BACKUP_ABS"

  # Find YAML files (both .yaml and .yml)
  mapfile -t files < <(find "$ROOT_ABS" -type f \( -iname '*.yaml' -o -iname '*.yml' \))
  if ((${#files[@]} == 0)); then
    log "No YAML files found."
    exit 0
  fi

  for f in "${files[@]}"; do
    process_one "$f"
  done

  log "Done."
  log "Files modified:            $touched"
  log "XML wrappers removed:      $xml_stripped"
  log "`other:` blocks removed:   $other_removed"
  log "'create-plan-branch' drops: $create_removed"

  # quick spot checks
  echo
  echo "Quick checks (should all be 0):"
  echo -n "  files starting with XML header: "
  find "$ROOT_ABS" -type f -iname '*.y*ml' -exec head -n1 {} \; | grep -c '^<\?xml' || true
  echo -n "  files still containing concurrent-build-plugin: "
  grep -R -l 'concurrent-build-plugin' "$ROOT_ABS" | wc -l || true
  echo -n "  files still containing create-plan-branch: "
  grep -R -l 'create-plan-branch' "$ROOT_ABS" | wc -l || true
}

main "$@"