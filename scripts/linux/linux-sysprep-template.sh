#!/usr/bin/env bash
# Safely generalize a Linux VM before shutting down and converting into a template.
# Safety tags: [ROOT] [DESTRUCTIVE] [REBOOT]

set -euo pipefail

CONFIRMED="false"
POWEROFF="false"

usage() {
  cat <<'EOF'
Usage: linux-sysprep-template.sh --confirm [--poweroff]

Prepares a Linux VM to be cloned as a clean template (Proxmox/KVM/VMware):
  - Truncates /etc/machine-id and relinks /var/lib/dbus/machine-id
  - Deletes /etc/ssh/ssh_host_* keys (regenerated on cloned VM first boot)
  - Cleans cloud-init state if cloud-init is installed
  - Cleans package manager caches and rotates/truncates system logs
  - Removes shell history and temporary files

Options:
  --confirm    Required safety flag confirming this host is a VM template
  --poweroff   Immediately power off the VM after cleanup completes
  -h, --help   Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRMED="true"
      shift
      ;;
    --poweroff)
      POWEROFF="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: Must run as root (use sudo)." >&2
  exit 1
fi

if [[ "${CONFIRMED}" != "true" ]]; then
  echo "Error: Refusing to run destructive sysprep without --confirm." >&2
  echo "Run with --help for details." >&2
  exit 1
fi

echo "[1/6] Stopping logging services..."
systemctl stop rsyslog 2>/dev/null || true
systemctl stop auditd 2>/dev/null || true

echo "[2/6] Cleaning package caches..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get autoremove -y >/dev/null 2>&1 || true
  apt-get clean
elif command -v dnf >/dev/null 2>&1; then
  dnf clean all
elif command -v zypper >/dev/null 2>&1; then
  zypper clean --all
fi

echo "[3/6] Resetting machine-id (preserving 0-byte file for systemd regeneration)..."
truncate -s 0 /etc/machine-id
if [[ -f /var/lib/dbus/machine-id ]]; then
  rm -f /var/lib/dbus/machine-id
  ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

echo "[4/6] Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# Ensure Debian/Ubuntu systems regenerate SSH host keys on first boot if cloud-init is absent
if command -v dpkg-reconfigure >/dev/null 2>&1 && ! command -v cloud-init >/dev/null 2>&1; then
  cat <<'EOF' > /etc/systemd/system/regenerate-ssh-host-keys.service
[Unit]
Description=Regenerate SSH host keys on first boot
Before=ssh.service
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

[Service]
Type=oneshot
ExecStart=/usr/sbin/dpkg-reconfigure -f noninteractive openssh-server
ExecStartPost=/bin/systemctl disable regenerate-ssh-host-keys.service

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable regenerate-ssh-host-keys.service
fi

echo "[5/6] Cleaning cloud-init state and DHCP leases..."
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init clean --logs --seed || cloud-init clean --logs || true
fi
rm -f /var/lib/dhcp/* /var/lib/dhclient/* /var/lib/NetworkManager/*.lease 2>/dev/null || true

echo "[6/6] Truncating logs, temp directories, and shell histories..."
journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=1s 2>/dev/null || true
find /var/log -type f -name '*.gz' -delete 2>/dev/null || true
find /var/log -type f -name '*.[0-9]' -delete 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -rf /tmp/* /var/tmp/*
rm -f /root/.bash_history /home/*/.bash_history 2>/dev/null || true
unset HISTFILE || true

sync

echo "Sysprep complete. Do not reboot back into this template; power off and convert to template."
if [[ "${POWEROFF}" == "true" ]]; then
  poweroff
fi
