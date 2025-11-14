#!/usr/bin/env bash
START_DATE=$(date -d 'yesterday 23:00' +'%Y-%m-%d %H')
END_DATE=$(date -d 'today 01:59' +'%Y-%m-%d %H')

find "$LOGROOT" -type f \( -name '*.log' -o -name '*.gz' \) -print0 \
| xargs -0 zgrep -ai --with-filename --line-number "$PATTERN" \
| awk -v s="$START_DATE" -v e="$END_DATE" '
    { ts=$0; if (ts>=s && ts<=e) print }'