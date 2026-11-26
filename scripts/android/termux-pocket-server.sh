#!/usr/bin/env bash
# Bootstrap an F-Droid Termux environment as a 24/7 pocket Linux server.
# Safety tags: [NON-ROOT]

set -euo pipefail

AUTHORIZED_KEY_FILE=""
ENABLE_BOOT_SCRIPT="true"

usage() {
  cat <<'EOF'
Usage: termux-pocket-server.sh [OPTIONS]

Bootstraps F-Droid Termux as a headless pocket Linux server:
  - Upgrades packages and installs openssh, tmux, termux-services, and ops CLI tools
  - Enables sshd on port 8022 via runit (termux-services)
  - Acquires wake-lock and writes ~/.termux/boot/00-pocket-server.sh for Termux:Boot
  - Optionally installs an SSH public key and locks sshd to key-only authentication

Options:
  --pubkey <file>   Append public key file to ~/.ssh/authorized_keys and disable password auth
  --no-boot-script  Skip creating ~/.termux/boot/00-pocket-server.sh
  -h, --help        Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pubkey)
      AUTHORIZED_KEY_FILE="${2:-}"
      shift 2
      ;;
    --no-boot-script)
      ENABLE_BOOT_SCRIPT="false"
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

if [[ -z "${PREFIX:-}" || ! -d "${PREFIX}" || "${PREFIX}" != *"/com.termux/"* ]]; then
  echo "Error: Run this script inside Termux (F-Droid build)." >&2
  exit 1
fi

echo "[1/5] Updating Termux packages..."
pkg update -y
pkg upgrade -y

echo "[2/5] Installing OpenSSH, tmux, termux-services, and core ops packages..."
pkg install -y \
  openssh \
  tmux \
  termux-services \
  termux-api \
  iproute2 \
  curl \
  wget \
  jq \
  htop \
  ncdu \
  ripgrep \
  rsync \
  git \
  dnsutils \
  nmap

echo "[3/5] Configuring SSH (~/.ssh and sshd on port 8022)..."
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
touch "${HOME}/.ssh/authorized_keys"
chmod 600 "${HOME}/.ssh/authorized_keys"

if [[ -n "${AUTHORIZED_KEY_FILE}" ]]; then
  if [[ ! -f "${AUTHORIZED_KEY_FILE}" ]]; then
    echo "Error: Public key file not found: ${AUTHORIZED_KEY_FILE}" >&2
    exit 1
  fi
  cat "${AUTHORIZED_KEY_FILE}" >> "${HOME}/.ssh/authorized_keys"
  sort -u -o "${HOME}/.ssh/authorized_keys" "${HOME}/.ssh/authorized_keys"

  SSHD_CONF="${PREFIX}/etc/ssh/sshd_config"
  if [[ -f "${SSHD_CONF}" ]]; then
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONF}"
    if ! grep -q '^PasswordAuthentication' "${SSHD_CONF}"; then
      echo 'PasswordAuthentication no' >> "${SSHD_CONF}"
    fi
  fi
  echo "Installed public key and disabled SSH password authentication."
else
  echo "No --pubkey supplied. Set a password with 'passwd' or add your key to ~/.ssh/authorized_keys."
fi

echo "[4/5] Acquiring wake-lock and configuring Termux:Boot autostart..."
termux-wake-lock || true

if [[ "${ENABLE_BOOT_SCRIPT}" == "true" ]]; then
  mkdir -p "${HOME}/.termux/boot"
  cat <<'EOF' > "${HOME}/.termux/boot/00-pocket-server.sh"
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
. "$PREFIX/etc/profile"
sshd
EOF
  chmod +x "${HOME}/.termux/boot/00-pocket-server.sh"
fi

echo "[5/5] Enabling sshd service..."
if command -v sv-enable >/dev/null 2>&1; then
  sv-enable sshd || true
fi
sshd || true

LAN_IP="$(ip -4 -o addr show 2>/dev/null | awk '!/127\.0\.0\.1/ {split($4,a,"/"); print a[1]; exit}')"
echo "Termux pocket server ready."
echo "Connect via: ssh -p 8022 $(whoami)@${LAN_IP:-<DEVICE_IP>}"
echo "Reminder: Disable Android battery optimization for Termux and disable Phantom Process Killer via ADB on Android 12+."
