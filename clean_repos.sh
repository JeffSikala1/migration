#!/usr/bin/env bash
set -euo pipefail

# Path to the INNER specs folder (override with: SPEC_DIR=/path ./clean_repos.sh)
SPEC_DIR="${SPEC_DIR:-$(pwd)/bamboo-specs}"

BACKUP_DIR="$(pwd)/backup-repos-$(date +%F-%H%M%S)"
DRY_RUN=0
[[ "${1-}" == "--dry-run" ]] && { DRY_RUN=1; shift || true; }

log(){ printf '[%(%F %T)T] %s\n' -1 "$*"; }

shopt -s nullglob

# Collect target files: plan YAMLs only (skip perms + manifest)
files=()
for f in "$SPEC_DIR"/*.yaml; do
  base="${f##*/}"
  [[ "$base" == "bamboo.yml" ]] && continue
  [[ "$base" == *.perms.yaml ]] && continue
  files+=("$f")
done

[[ ${#files[@]} -eq 0 ]] && { log "No matching plan YAMLs in $SPEC_DIR"; exit 0; }

mkdir -p "$BACKUP_DIR"

changed=0
processed=0
log "Scanning ${#files[@]} file(s) under $SPEC_DIR"

for f in "${files[@]}"; do
  ((processed++))
  tmp="$(mktemp)"

  gawk '
    function lspace(s,  m){ m=match(s,/^[ \t]*/); return RLENGTH }

    BEGIN{
      inrepos=0; repos_indent=0;
      list_indent=-1;            # indent where "- name:" appears
    }

    {
      line = $0

      # reset state on YAML doc separators
      if (line ~ /^---[[:space:]]*$/ || line ~ /^\.\.\.[[:space:]]*$/) {
        inrepos=0; list_indent=-1;
        print line; next
      }

      if (!inrepos) {
        if (line ~ /^[[:space:]]*repositories:[[:space:]]*$/) {
          repos_indent = lspace(line)
          list_indent  = -1
          inrepos      = 1
          print line
          next
        } else { print line; next }
      }

      # inside repositories block
      ind = lspace(line)

      # new list item? (dash + name + colon)
      if (line ~ /^[[:space:]]*-[[:space:]]+[^:]+:[[:space:]]*$/) {
        if (list_indent < 0) list_indent = ind  # capture real indent of the first item

        if (ind == list_indent) {
          name = line
          sub(/^[[:space:]]*-[[:space:]]+/,"",name)
          sub(/[[:space:]]*:[[:space:]]*$/,"",name)

          # emit minimal entry and drop original nested attributes
          printf "%*s- %s:\n", list_indent, "", name
          printf "%*s  scope: global\n", list_indent, ""
          next
        }
      }

      # leaving repositories: first non-blank line back at or above the block indent
      if (ind <= repos_indent && line !~ /^[[:space:]]*$/) {
        inrepos=0; list_indent=-1
        print line
        next
      }

      # otherwise we are still inside repositories -> drop nested lines
      next
    }
  ' "$f" > "$tmp"

  if ! cmp -s "$f" "$tmp"; then
    log "Update: ${f#$SPEC_DIR/}"
    cp -p -- "$f" "$BACKUP_DIR/"
    if (( DRY_RUN )); then
      rm -f -- "$tmp"
    else
      mv -- "$tmp" "$f"
    fi
    ((changed++))
  else
    rm -f -- "$tmp"
  fi
done

if (( DRY_RUN )); then
  log "Dry-run: $changed file(s) would change. Backups NOT written."
else
  log "Done: $changed file(s) changed. Backups in: $BACKUP_DIR"
fi
log "Processed: $processed file(s)"