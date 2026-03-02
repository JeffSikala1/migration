#!/usr/bin/env bash
set -Eeuo pipefail

# Run as ec2-user with sudo or as root
USR=jsikala
UIDN=$(id -u "$USR" 2>/dev/null || true)

# Prevent systemd user session from relaunching
sudo loginctl disable-linger "$USR" 2>/dev/null || true

# Terminate the user’s systemd session(s)
sudo loginctl terminate-user "$USR" 2>/dev/null || true

# If user@UID is still around, stop and kill it hard
if [ -n "$UIDN" ]; then
  sudo systemctl stop "user@${UIDN}.service" 2>/dev/null || true
  sudo systemctl kill --kill-who=all --signal=SIGKILL "user@${UIDN}.service" 2>/dev/null || true
fi

# Kill VS Code server / node remnants owned by the user
sudo pkill -u "$USR" -f 'vscode-server|node' 2>/dev/null || true

# As a final hammer, kill ALL processes for that user
sudo pkill -KILL -u "$USR" 2>/dev/null || true