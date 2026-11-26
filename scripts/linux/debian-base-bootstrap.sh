#!/usr/bin/env bash
# Standard production bootstrap for Debian 12+ and Ubuntu Server 22.04/24.04 hosts.
# Safety tags: [ROOT]

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

INSTALL_GUEST_AGENT="true"
ENABLE_UNATTENDED="true"

usage() {
  cat <<'EOF'
Usage: debian-base-bootstrap.sh [OPTIONS]

Bootstraps a fresh Debian or Ubuntu Server:
  - Runs apt update and full-upgrade
  - Installs core sysadmin and network diagnostic packages
  - Configures chrony for accurate NTP time sync
  - Configures unattended-upgrades for security patches
  - Applies container-safe kernel sysctl baseline

Options:
  --no-guest-agent         Skip installing qemu-guest-agent (e.g. bare metal)
  --no-unattended          Skip configuring unattended-upgrades
  -h, --help               Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-guest-agent)
      INSTALL_GUEST_AGENT="false"
      shift
      ;;
    --no-unattended)
      ENABLE_UNATTENDED="false"
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

if ! command -v apt-get >/dev/null 2>&1; then
  echo "Error: apt-get not found. Intended for Debian/Ubuntu systems." >&2
  exit 1
fi

echo "[1/5] Updating apt metadata and upgrading system..."
apt-get update -y
apt-get full-upgrade -y

echo "[2/5] Installing core sysadmin packages..."
PACKAGES=(
  ca-certificates
  curl
  wget
  gnupg
  jq
  tmux
  vim
  git
  rsync
  htop
  ncdu
  lsof
  dnsutils
  mtr-tiny
  tcpdump
  iproute2
  netcat-openbsd
  unzip
  zstd
  bash-completion
  chrony
)

if [[ "${INSTALL_GUEST_AGENT}" == "true" ]]; then
  PACKAGES+=(qemu-guest-agent)
fi

apt-get install -y --no-install-recommends "${PACKAGES[@]}"

echo "[3/5] Enabling chrony time synchronization..."
if systemctl is-enabled systemd-timesyncd >/dev/null 2>&1; then
  systemctl disable --now systemd-timesyncd || true
fi
systemctl enable --now chrony
if [[ "${INSTALL_GUEST_AGENT}" == "true" ]]; then
  systemctl enable --now qemu-guest-agent || true
fi

if [[ "${ENABLE_UNATTENDED}" == "true" ]]; then
  echo "[4/5] Configuring unattended-upgrades (security patches only, no auto-reboot)..."
  apt-get install -y unattended-upgrades apt-listchanges
  cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
  cat <<'EOF' > /etc/apt/apt.conf.d/51unattended-upgrades-local
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
else
  echo "[4/5] Skipping unattended-upgrades (--no-unattended)."
fi

echo "[5/5] Applying production-safe sysctl hardening baseline..."
cat <<'EOF' > /etc/sysctl.d/99-base-hardening.conf
# Network hardening (safe for Docker/K8s/routing)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Kernel & memory safety
kernel.kptr_restrict = 1
kernel.dmesg_restrict = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
vm.swappiness = 10

# Modern TCP congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system

apt-get autoremove -y
apt-get clean

echo "Bootstrap complete. Verify time sync with: chronyc tracking"
