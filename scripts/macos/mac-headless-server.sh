#!/usr/bin/env bash
# Configure a Mac Mini / macOS host for 24/7 headless server operation, SSH, and Homebrew tools.
# Safety tags: [ROOT]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${SCRIPT_DIR}/Brewfile.server"
SKIP_BREW="false"
ENABLE_FIREWALL="true"

usage() {
  cat <<'EOF'
Usage: sudo mac-headless-server.sh [OPTIONS]

Configures a macOS host for 24/7 headless server operation:
  - Disables system/display/disk sleep and Power Nap via pmset
  - Enables auto-restart after power failure (autorestart 1) and Wake-on-LAN (womp 1)
  - Enables Remote Login (SSH)
  - Enables macOS Application Firewall (optional)
  - Installs packages from Brewfile.server as the invoking non-root user

Options:
  --skip-brew          Skip 'brew bundle' package installation
  --no-firewall        Do not modify Application Firewall settings
  --brewfile <path>    Path to a custom Brewfile (default: ./Brewfile.server)
  -h, --help           Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-brew)
      SKIP_BREW="true"
      shift
      ;;
    --no-firewall)
      ENABLE_FIREWALL="false"
      shift
      ;;
    --brewfile)
      BREWFILE="${2:-}"
      shift 2
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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: This script must run on macOS (Darwin)." >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: Must run as root (use sudo)." >&2
  exit 1
fi

echo "[1/4] Applying 24/7 headless power management settings via pmset..."
pmset -a sleep 0
pmset -a displaysleep 0
pmset -a disksleep 0
pmset -a autorestart 1
pmset -a womp 1
pmset -a powernap 0
pmset -a tcpkeepalive 1

echo "[2/4] Enabling Remote Login (OpenSSH)..."
systemsetup -setremotelogin on >/dev/null 2>&1 || launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true

if [[ "${ENABLE_FIREWALL}" == "true" ]]; then
  echo "[3/4] Enabling macOS Application Firewall..."
  /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
else
  echo "[3/4] Skipping Application Firewall (--no-firewall)."
fi

if [[ "${SKIP_BREW}" == "false" ]]; then
  echo "[4/4] Applying Brewfile: ${BREWFILE}..."
  if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    echo "Warning: Invoke via 'sudo' from a regular user so Homebrew runs non-root. Skipping brew bundle." >&2
  elif [[ ! -f "${BREWFILE}" ]]; then
    echo "Warning: Brewfile not found at ${BREWFILE}. Skipping brew bundle." >&2
  else
    BREW_BIN=""
    if [[ -x /opt/homebrew/bin/brew ]]; then
      BREW_BIN="/opt/homebrew/bin/brew"
    elif [[ -x /usr/local/bin/brew ]]; then
      BREW_BIN="/usr/local/bin/brew"
    fi

    if [[ -n "${BREW_BIN}" ]]; then
      sudo -u "${SUDO_USER}" "${BREW_BIN}" bundle --file="${BREWFILE}"
    else
      echo "Warning: Homebrew not installed. Install from https://brew.sh then run: brew bundle --file=${BREWFILE}" >&2
    fi
  fi
else
  echo "[4/4] Skipping Homebrew installation (--skip-brew)."
fi

echo "Done. Active pmset profile:"
pmset -g
echo "Note: If FileVault is enabled, remote reboots require 'sudo fdesetup authrestart' or physical unlock."
