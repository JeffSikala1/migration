#!/usr/bin/env bash
set -Eeuo pipefail
DOMAIN=cnxsartifact
REPO=conexus-plugin-repository
NS=test.ca
REGION=us-east-1

export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token \
  --domain "$DOMAIN" --query authorizationToken --output text --region "$REGION")

purge_pkg () {
  local pkg="$1"
  # archive any SNAPSHOT pointers
  aws codeartifact update-package-versions-status \
    --domain "$DOMAIN" --repository "$REPO" \
    --format maven --namespace "$NS" --package "$pkg" \
    --versions 0.0.1-SNAPSHOT --target-status Archived >/dev/null 2>&1 || true

  # list all versions then delete them
  mapfile -t vers < <(aws codeartifact list-package-versions \
    --domain "$DOMAIN" --repository "$REPO" --format maven \
    --namespace "$NS" --package "$pkg" \
    --query 'versions[].version' --output text | tr '\t' '\n' | sed '/^$/d')
  if ((${#vers[@]})); then
    aws codeartifact delete-package-versions \
      --domain "$DOMAIN" --repository "$REPO" \
      --format maven --namespace "$NS" --package "$pkg" \
      --versions "${vers[@]}"
  fi
}

purge_pkg smoke
purge_pkg hello
echo "Cleanup complete."