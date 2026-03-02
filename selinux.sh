sudo bash -eux <<'EOF'
# 0) Tools
dnf install -y policycoreutils policycoreutils-python-utils setools-console selinux-policy-targeted || true

# 1) Flip SELinux to enforcing (persist + now)
if ! grep -q '^SELINUX=enforcing' /etc/selinux/config; then
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

if sestatus | grep -qi 'disabled'; then
  # If it was disabled, make sure kernel enables it and relabel on reboot
  if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="selinux=1 /' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
  touch /.autorelabel
  echo "SELinux was disabled: a reboot is required (and will relabel)."
else
  # If it was permissive, enforce immediately
  setenforce 1 || true
fi

# 2) Harden common exec paths
# /tmp as tmpfs with noexec (persistent)
if ! grep -qE '^\s*tmpfs\s+/tmp\s+' /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec,mode=1777 0 0" >> /etc/fstab
fi
mountpoint -q /tmp && mount -o remount,nodev,nosuid,noexec /tmp || mount /tmp

# /var/tmp bind to /tmp with same flags (persistent)
if ! grep -qE '^\s*/tmp\s+/var/tmp\s+none\s+bind' /etc/fstab; then
  echo "/tmp /var/tmp none bind 0 0" >> /etc/fstab
  echo "/tmp /var/tmp none bind,remount,nodev,nosuid,noexec 0 0" >> /etc/fstab
fi
mount /var/tmp || true
mount -o remount,bind,nodev,nosuid,noexec /var/tmp || true

# /dev/shm hardened (persistent)
if ! grep -qE '^\s*tmpfs\s+/dev/shm\s+' /etc/fstab; then
  echo "tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec,mode=1777 0 0" >> /etc/fstab
fi
mount -o remount,nodev,nosuid,noexec /dev/shm || mount /dev/shm

# 3) SELinux booleans: block exec from user dirs
setsebool -P user_exec_content off || true
setsebool -P staff_exec_content off || true

echo "--- STATUS ---"
getenforce || true
mount | egrep '(/tmp|/var/tmp|/dev/shm)'
EOF