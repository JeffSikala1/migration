#!/bin/bash

dockerhits=$(find /var/lib/docker/overlay2 -path "*/diff/*" -name "*commons-text-1.[0-9].jar" 2>/dev/null)
currentdate=$(date '+%Y-%m-%d')
LOG=/var/log/apache_commons_pre_1_10_removed.log

for i in $dockerhits; do
  if rm -f "$i" 2>/dev/null; then
    echo "$currentdate - removed: $i" >> "$LOG"
  else
    echo "$currentdate - FAILED to remove (file may have been deleted): $i" >> "$LOG"
  fi
done