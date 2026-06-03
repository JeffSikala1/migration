#!/usr/bin/env bash
# =============================================================================
# ec2_investigate.sh
# GSA CNXS - EC2 Environment Documentation Script
# Run as root (or via sudo) on each host: .34, .35, .243
# Output is saved to /tmp/ec2_report_<hostname>_<date>.txt
# =============================================================================

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
DATE=$(date '+%Y-%m-%d_%H%M')
OUTFILE="/tmp/ec2_report_${HOSTNAME}_${DATE}.txt"

section() {
  echo "" >> "$OUTFILE"
  echo "============================================================" >> "$OUTFILE"
  echo "  $1" >> "$OUTFILE"
  echo "============================================================" >> "$OUTFILE"
}

run() {
  echo "--- $1 ---" >> "$OUTFILE"
  eval "$2" >> "$OUTFILE" 2>&1
  echo "" >> "$OUTFILE"
}

echo "Starting EC2 investigation on $HOSTNAME at $DATE"
echo "Output: $OUTFILE"
echo "" > "$OUTFILE"
echo "EC2 ENVIRONMENT REPORT — $HOSTNAME — $DATE" >> "$OUTFILE"


# ------------------------------------------------------------
section "1. INSTANCE IDENTITY"
# ------------------------------------------------------------
run "Hostname" "hostname -f"
run "OS Release" "cat /etc/os-release"
run "Kernel Version" "uname -r"
run "System Uptime" "uptime"
run "EC2 Instance Metadata (IMDSv2)" "
  TOKEN=\$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
  for META in instance-id instance-type ami-id placement/availability-zone local-ipv4 public-ipv4; do
    echo \"\$META: \$(curl -s -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/\$META)\"
  done
"


# ------------------------------------------------------------
section "2. STORAGE — VOLUMES, MOUNTS, FSTAB"
# ------------------------------------------------------------
run "Block Devices (lsblk)" "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,UUID"
run "Disk Usage (df -hT)" "df -hT"
run "fstab Contents" "cat /etc/fstab"
run "Currently Mounted Filesystems" "mount | grep -v 'tmpfs\|sysfs\|proc\|devpts\|cgroup\|mqueue\|hugetlb\|pts'"
run "LVM Volume Groups" "vgs 2>/dev/null || echo 'LVM not present or not accessible'"
run "LVM Logical Volumes" "lvs 2>/dev/null || echo 'LVM not present or not accessible'"
run "LVM Physical Volumes" "pvs 2>/dev/null || echo 'LVM not present or not accessible'"
run "Filesystem UUIDs (blkid)" "blkid"


# ------------------------------------------------------------
section "3. RUNNING SERVICES"
# ------------------------------------------------------------
run "All Active Services" "systemctl list-units --type=service --state=running --no-pager"
run "All Enabled Services" "systemctl list-unit-files --type=service --state=enabled --no-pager"
run "Failed Services" "systemctl --failed --no-pager"

# Docker is the primary service; NGINX/Postgres may still run on host on .34/.243
for SVC in docker nginx postgresql; do
  run "Service check: $SVC" "systemctl status $SVC --no-pager 2>/dev/null || echo 'Not found as systemd unit'"
done


# ------------------------------------------------------------
section "4. DOCKER — CONTAINERS, IMAGES, VOLUMES, NETWORKS"
# ------------------------------------------------------------
run "Docker Version" "docker version 2>/dev/null || echo 'docker not available'"
run "Docker Info (daemon config)" "docker info 2>/dev/null"
run "All Containers (running + stopped)" "docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null"
run "Container Inspect (all running)" "
  for CID in \$(docker ps -q 2>/dev/null); do
    echo \"\"
    echo \"========== Container: \$(docker inspect --format '{{.Name}}' \$CID) ==========\"
    docker inspect \$CID --format '
Name:        {{.Name}}
Image:       {{.Config.Image}}
Restart:     {{.HostConfig.RestartPolicy.Name}}
Status:      {{.State.Status}}
StartedAt:   {{.State.StartedAt}}
Mounts:
{{range .Mounts}}  - Type={{.Type}} Src={{.Source}} -> Dst={{.Destination}} RW={{.RW}}
{{end}}Ports:
{{range \$p, \$b := .NetworkSettings.Ports}}  - {{$p}} -> {{$b}}
{{end}}Env:
{{range .Config.Env}}  {{.}}
{{end}}' 2>/dev/null
  done
"
run "Docker Named Volumes" "docker volume ls 2>/dev/null"
run "Docker Volume Details" "
  for VOL in \$(docker volume ls -q 2>/dev/null); do
    echo \"--- \$VOL ---\"
    docker volume inspect \$VOL 2>/dev/null
  done
"
run "Docker Networks" "docker network ls 2>/dev/null"
run "Docker Network Details" "
  for NET in \$(docker network ls -q 2>/dev/null); do
    NAME=\$(docker network inspect \$NET --format '{{.Name}}' 2>/dev/null)
    echo \"--- \$NAME ---\"
    docker network inspect \$NET --format 'Driver: {{.Driver}}  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null
  done
"
run "Docker Images" "docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null"
run "Docker Compose Files (find)" "find / -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' 2>/dev/null | grep -v proc | grep -v sys"
run "Docker Daemon Config" "cat /etc/docker/daemon.json 2>/dev/null || echo 'No daemon.json found'"
run "Docker Storage Driver & Root Dir" "docker info 2>/dev/null | grep -E 'Storage Driver|Docker Root Dir|Logging Driver'"
run "Docker Root Dir Disk Usage" "docker system df 2>/dev/null"


# ------------------------------------------------------------
section "5. RUNNING PROCESSES & PORTS"
# ------------------------------------------------------------
run "All Listening Ports (ss)" "ss -tlnp"
run "Host-level NGINX Config Test" "nginx -t 2>&1 || echo 'nginx not installed on host'"


# ------------------------------------------------------------
section "6. SECURITY — SELINUX & FIPS"
# ------------------------------------------------------------
run "SELinux Status" "sestatus 2>/dev/null || echo 'sestatus not available'"
run "SELinux Config File" "cat /etc/selinux/config 2>/dev/null || echo 'No SELinux config'"
run "FIPS Mode Status" "cat /proc/sys/crypto/fips_enabled 2>/dev/null && echo '(1=enabled, 0=disabled)' || echo 'FIPS check not available'"
run "FIPS Kernel Param Check" "grep -i fips /etc/default/grub 2>/dev/null || echo 'No FIPS param in grub'"
run "OpenSSL FIPS Check" "openssl version -a 2>/dev/null"


# ------------------------------------------------------------
section "7. NETWORK"
# ------------------------------------------------------------
run "Network Interfaces (ip addr)" "ip addr show"
run "Routing Table" "ip route"
run "DNS Config (/etc/resolv.conf)" "cat /etc/resolv.conf"
run "Hosts File (/etc/hosts)" "cat /etc/hosts"
run "Active Firewall Rules (firewalld)" "firewall-cmd --list-all 2>/dev/null || echo 'firewalld not running'"
run "iptables rules" "iptables -L -n --line-numbers 2>/dev/null | head -60"


# ------------------------------------------------------------
section "8. USERS & ACCESS"
# ------------------------------------------------------------
run "Users with Shell Access" "grep -E '/bin/bash|/bin/sh|/bin/zsh' /etc/passwd"
run "Sudoers (main file)" "cat /etc/sudoers 2>/dev/null | grep -v '^#' | grep -v '^$'"
run "Sudoers.d contents" "ls /etc/sudoers.d/ 2>/dev/null && grep -rh . /etc/sudoers.d/ 2>/dev/null | grep -v '^#' | grep -v '^$'"
run "Last Logins" "last | head -20"
run "Currently Logged In" "who"


# ------------------------------------------------------------
section "9. SCHEDULED TASKS"
# ------------------------------------------------------------
run "Root Crontab" "crontab -l 2>/dev/null || echo 'No root crontab'"
run "System Cron directories" "
  for DIR in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
    echo \"=== \$DIR ===\"
    ls -la \$DIR 2>/dev/null
  done
"
run "All User Crontabs" "
  for USER in \$(cut -f1 -d: /etc/passwd); do
    CTAB=\$(crontab -u \$USER -l 2>/dev/null)
    if [ -n \"\$CTAB\" ]; then
      echo \"--- \$USER ---\"
      echo \"\$CTAB\"
    fi
  done
"


# ------------------------------------------------------------
section "10. INSTALLED PACKAGES OF INTEREST"
# ------------------------------------------------------------
run "Key Package Versions" "
  for PKG in docker-ce docker-ce-cli containerd.io docker-compose-plugin nginx postgresql git openssl curl awscli amazon-ssm-agent; do
    echo -n \"\$PKG: \"
    rpm -q \$PKG 2>/dev/null || echo 'not installed'
  done
"
run "Docker Compose (standalone) Version" "docker-compose --version 2>/dev/null || docker compose version 2>/dev/null || echo 'not found'"


# ------------------------------------------------------------
section "11. HOST APPLICATION PATHS & CONFIG POINTERS"
# ------------------------------------------------------------
run "Docker Compose File Contents (all found)" "
  find / -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' 2>/dev/null | grep -v proc | grep -v sys | while read F; do
    echo \"\"
    echo \"========== \$F ==========\"
    cat \"\$F\"
  done
"
run "Host NGINX Config Files" "find /etc/nginx -type f -name '*.conf' 2>/dev/null | head -20"
run "Host NGINX Config Contents" "
  find /etc/nginx -type f -name '*.conf' 2>/dev/null | while read F; do
    echo \"\"
    echo \"========== \$F ==========\"
    cat \"\$F\"
  done
"
run "Common Host Data/Config Directories" "
  for DIR in /opt/atlassian /var/atlassian /opt/artifactory /opt/jfrog /var/lib/pgsql /etc/nginx /opt/docker /srv; do
    if [ -d \"\$DIR\" ]; then
      echo \"EXISTS: \$DIR\"
      ls -la \"\$DIR\"
    fi
  done
"
run "systemd Unit File for Docker" "
  FILE=\$(systemctl show -p FragmentPath docker 2>/dev/null | cut -d= -f2)
  [ -n \"\$FILE\" ] && cat \"\$FILE\" || echo 'docker unit file not found'
"


# ------------------------------------------------------------
section "12. SYSTEM HEALTH SNAPSHOT"
# ------------------------------------------------------------
run "Memory Usage" "free -h"
run "CPU Info" "lscpu | grep -E 'Model name|CPU\(s\)|Thread|Socket|NUMA'"
run "Load Average" "cat /proc/loadavg"
run "Top Disk Consumers (top 20)" "du -sh /opt/* /var/* /home/* /tmp/* 2>/dev/null | sort -rh | head -20"
run "Inode Usage" "df -i | grep -v tmpfs"
run "Swap" "swapon --show"
run "Recent Kernel/System Messages" "journalctl -k --no-pager -n 30 2>/dev/null"
run "Recent Boot Messages" "journalctl -b --no-pager -n 50 2>/dev/null"


# ------------------------------------------------------------
echo "" >> "$OUTFILE"
echo "=== END OF REPORT ===" >> "$OUTFILE"

echo ""
echo "Done. Report saved to: $OUTFILE"
echo "To pull it back: scp <user>@<host>:$OUTFILE ."