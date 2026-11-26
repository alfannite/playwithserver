#!/usr/bin/env bash
# Prepare a Rocky Linux 9 / AlmaLinux 9 / RHEL 9 VM for Kubernetes or K3s nodes.
# Safety tags: [ROOT] [REBOOT]

set -euo pipefail

SELINUX_MODE="permissive"
SKIP_UPGRADE="false"

usage() {
  cat <<'EOF'
Usage: rocky-k8s-template.sh [OPTIONS]

Prepares a Rocky/Alma/RHEL 9 host for Kubernetes/K3s:
  - Enables EPEL and CRB repositories
  - Installs sysadmin packages and qemu-guest-agent
  - Disables swap immediately and in /etc/fstab
  - Loads overlay and br_netfilter kernel modules permanently
  - Applies Kubernetes networking sysctl parameters
  - Configures SELinux (default: permissive)

Options:
  --selinux-enforcing   Keep SELinux in enforcing mode instead of permissive
  --skip-upgrade        Skip full 'dnf upgrade -y' step
  -h, --help            Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --selinux-enforcing)
      SELINUX_MODE="enforcing"
      shift
      ;;
    --skip-upgrade)
      SKIP_UPGRADE="true"
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

if [[ ! -f /etc/redhat-release ]]; then
  echo "Error: /etc/redhat-release not found. Intended for RHEL/Rocky/Alma 9." >&2
  exit 1
fi

echo "[1/7] Enabling EPEL and CRB repositories..."
dnf install -y epel-release dnf-plugins-core
if dnf repolist --all | grep -qE '^crb\b'; then
  dnf config-manager --set-enabled crb
fi

if [[ "${SKIP_UPGRADE}" == "false" ]]; then
  echo "[2/7] Upgrading installed packages..."
  dnf upgrade -y --refresh
else
  echo "[2/7] Skipping package upgrade (--skip-upgrade)."
fi

echo "[3/7] Installing base sysadmin tools and qemu-guest-agent..."
dnf install -y \
  qemu-guest-agent \
  chrony \
  curl \
  wget \
  jq \
  tmux \
  vim-enhanced \
  git \
  rsync \
  bash-completion \
  bind-utils \
  iproute-tc \
  tcpdump \
  htop \
  lsof \
  ncdu \
  tar \
  zstd \
  socat \
  conntrack-tools \
  iptables-nft

systemctl enable --now qemu-guest-agent chronyd

echo "[4/7] Disabling swap immediately and persistently..."
swapoff -a
if grep -qE '^\s*[^#].*\sswap\s' /etc/fstab; then
  cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  sed -ri '/^\s*[^#].*\sswap\s/s/^/# /' /etc/fstab
fi

echo "[5/7] Configuring kernel modules (overlay, br_netfilter)..."
cat <<'EOF' > /etc/modules-load.d/99-kubernetes.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "[6/7] Applying Kubernetes sysctl settings..."
cat <<'EOF' > /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding        = 1
fs.inotify.max_user_watches         = 524288
fs.inotify.max_user_instances       = 512
EOF
sysctl --system

echo "[7/7] Configuring SELinux mode: ${SELINUX_MODE}..."
if [[ -f /etc/selinux/config ]]; then
  if [[ "${SELINUX_MODE}" == "permissive" ]]; then
    setenforce 0 || true
    sed -ri 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
  else
    sed -ri 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  fi
fi

echo "Done. Reboot recommended before installing container runtime / kubeadm or running sysprep."
