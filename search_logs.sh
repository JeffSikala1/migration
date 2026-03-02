#!/usr/bin/env bash
PATTERN="$1"                                   # pass phrase as arg

LOGROOT="/app/jboss-eap-8.0/standalone"

if [ -z "$PATTERN" ]; then
  echo "Usage: $0 \"search phrase\"" >&2
  exit 1
fi

find "$LOGROOT" -type f \( -name '*.log' -o -name '*.gz' \) -print0 |
  xargs -0 zgrep -ai --with-filename --line-number "$PATTERN"