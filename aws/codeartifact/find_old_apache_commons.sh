#!/bin/bash
# Removes vulnerable Apache Commons Text 1.0-1.9 jars from Docker layers.

dockerhits=$(find /app/docker -name "*commons-text-1.[0-9].jar" 2>/dev/null)
currentdate=$(date '+%Y-%m-%d')

LOG=/var/log/apache_commons_cleanup.log

for i in $dockerhits; do
  echo "$currentdate - removed docker hit: $i" >> "$LOG"
  rm -f "$i"
done