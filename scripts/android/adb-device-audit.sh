#!/usr/bin/env bash
# Collect hardware, battery, thermal, storage, network, and service telemetry from an ADB device.
# Safety tags: [NON-ROOT]

set -euo pipefail

SERIAL=""
OUT_FILE=""

usage() {
  cat <<'EOF'
Usage: adb-device-audit.sh [OPTIONS]

Pulls a concise operational health report from a connected Android device via ADB:
  - Device identity, Android release, security patch, and A/B slot
  - Battery health, charge level, voltage, temperature, and charging state
  - Thermal zones / throttling status
  - Filesystem storage usage (/data and /storage)
  - Network interfaces, Wi-Fi IP, and Private DNS config
  - Memory summary and top running processes

Options:
  -s <serial>     Target specific ADB device serial or IP:port (required if >1 device connected)
  -o <file>       Write report to a file in addition to stdout
  -h, --help      Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s)
      SERIAL="${2:-}"
      shift 2
      ;;
    -o|--out)
      OUT_FILE="${2:-}"
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

if ! command -v adb >/dev/null 2>&1; then
  echo "Error: 'adb' not found in PATH. Install Android Platform-Tools." >&2
  exit 1
fi

ADB_CMD=(adb)
if [[ -n "${SERIAL}" ]]; then
  ADB_CMD+=(-s "${SERIAL}")
fi

if ! "${ADB_CMD[@]}" get-state >/dev/null 2>&1; then
  echo "Error: No reachable authorized ADB device (check 'adb devices' or pass -s <serial>)." >&2
  exit 1
fi

run_report() {
  echo "=== ANDROID DEVICE AUDIT ($(date -u '+%Y-%m-%dT%H:%M:%SZ')) ==="
  echo
  echo "--- Device Identity ---"
  echo "Model:          $("${ADB_CMD[@]}" shell getprop ro.product.model | tr -d '\r')"
  echo "Manufacturer:   $("${ADB_CMD[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
  echo "Android Ver:    $("${ADB_CMD[@]}" shell getprop ro.build.version.release | tr -d '\r') (SDK $("${ADB_CMD[@]}" shell getprop ro.build.version.sdk | tr -d '\r'))"
  echo "Security Patch: $("${ADB_CMD[@]}" shell getprop ro.build.version.security_patch | tr -d '\r')"
  echo "Active Slot:    $("${ADB_CMD[@]}" shell getprop ro.boot.slot_suffix | tr -d '\r')"
  echo "Uptime:         $("${ADB_CMD[@]}" shell uptime | tr -d '\r')"

  echo
  echo "--- Battery Telemetry ---"
  "${ADB_CMD[@]}" shell dumpsys battery | grep -E 'AC powered|USB powered|Wireless powered|status:|health:|level:|voltage:|temperature:' | tr -d '\r'

  echo
  echo "--- Thermal Status ---"
  "${ADB_CMD[@]}" shell dumpsys thermalservice 2>/dev/null | head -n 25 | tr -d '\r' || echo "thermalservice unavailable"

  echo
  echo "--- Storage Usage ---"
  "${ADB_CMD[@]}" shell df -h /data /storage/emulated 2>/dev/null | tr -d '\r'

  echo
  echo "--- Network Interfaces & Private DNS ---"
  "${ADB_CMD[@]}" shell ip -br addr 2>/dev/null | grep -E 'wlan|eth|rmnet|tun|tailscale|wg' | tr -d '\r' || true
  echo "Private DNS Mode:      $("${ADB_CMD[@]}" shell settings get global private_dns_mode | tr -d '\r')"
  echo "Private DNS Specifier: $("${ADB_CMD[@]}" shell settings get global private_dns_specifier | tr -d '\r')"

  echo
  echo "--- Memory & Top Processes ---"
  "${ADB_CMD[@]}" shell cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree' | tr -d '\r'
  echo
  "${ADB_CMD[@]}" shell top -b -n 1 -o %CPU,%MEM,USER,ARGS 2>/dev/null | head -n 18 | tr -d '\r' || \
    "${ADB_CMD[@]}" shell ps -A -o PID,USER,RSS,NAME | sort -k3 -nr | head -n 15 | tr -d '\r'

  echo
  echo "--- Phantom Process Killer Config (Android 12+) ---"
  "${ADB_CMD[@]}" shell device_config get activity_manager max_phantom_processes 2>/dev/null | tr -d '\r' || true
}

if [[ -n "${OUT_FILE}" ]]; then
  run_report | tee "${OUT_FILE}"
  echo
  echo "Report saved to ${OUT_FILE}"
else
  run_report
fi
