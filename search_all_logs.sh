#!/usr/bin/env bash
PATTERN="incrementing error count application property"
LOGROOT="/app/jboss-eap-8.0/standalone"

find "$LOGROOT" -type f \( -name '*.log' -o -name '*.gz' \) -print0 \
| xargs -0 zgrep -ai --with-filename --line-number "$PATTERN"