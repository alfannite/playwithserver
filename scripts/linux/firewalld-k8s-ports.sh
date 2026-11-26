#!/usr/bin/env bash
# Configure firewalld ports cleanly for Kubernetes / K3s control-plane or worker nodes.
# Safety tags: [ROOT]

set -euo pipefail

ROLE=""
ZONE=""
CNI="flannel"
DRY_RUN="false"

usage() {
  cat <<'EOF'
Usage: firewalld-k8s-ports.sh --role <control-plane|worker> [OPTIONS]

Opens required firewalld ports for Kubernetes / K3s without disabling firewalld.

Required:
  --role <control-plane|worker>   Node role determining which ports to open

Options:
  --cni <flannel|calico|cilium>   CNI overlay ports to open (default: flannel)
  --zone <zone>                   Target firewalld zone (default: active default zone)
  --dry-run                       Print firewall-cmd calls without applying changes
  -h, --help                      Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    --cni)
      CNI="${2:-}"
      shift 2
      ;;
    --zone)
      ZONE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
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

if [[ "${ROLE}" != "control-plane" && "${ROLE}" != "worker" ]]; then
  echo "Error: --role must be 'control-plane' or 'worker'." >&2
  usage >&2
  exit 1
fi

if [[ "${CNI}" != "flannel" && "${CNI}" != "calico" && "${CNI}" != "cilium" ]]; then
  echo "Error: --cni must be 'flannel', 'calico', or 'cilium'." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "false" && "${EUID}" -ne 0 ]]; then
  echo "Error: Must run as root (use sudo)." >&2
  exit 1
fi

if ! command -v firewall-cmd >/dev/null 2>&1; then
  echo "Error: firewall-cmd not found. Install and enable firewalld first." >&2
  exit 1
fi

if [[ -z "${ZONE}" ]]; then
  ZONE="$(firewall-cmd --get-default-zone)"
fi

run_fw() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] firewall-cmd $*"
  else
    firewall-cmd "$@"
  fi
}

PORTS=()

if [[ "${ROLE}" == "control-plane" ]]; then
  PORTS+=(
    "6443/tcp"        # Kubernetes API server
    "2379-2380/tcp"   # etcd server client & peer API
    "10250/tcp"       # Kubelet API
    "10257/tcp"       # kube-controller-manager
    "10259/tcp"       # kube-scheduler
  )
else
  PORTS+=(
    "10250/tcp"       # Kubelet API
    "10256/tcp"       # kube-proxy healthz
    "30000-32767/tcp" # NodePort services (TCP)
    "30000-32767/udp" # NodePort services (UDP)
  )
fi

case "${CNI}" in
  flannel)
    PORTS+=(
      "8472/udp"      # Flannel VXLAN
      "51820/udp"     # Flannel WireGuard IPv4
      "51821/udp"     # Flannel WireGuard IPv6
    )
    ;;
  calico)
    PORTS+=(
      "179/tcp"       # Calico BGP
      "4789/udp"      # Calico VXLAN
      "5473/tcp"      # Calico Typha
      "51820/udp"     # Calico WireGuard
    )
    ;;
  cilium)
    PORTS+=(
      "4240/tcp"      # Cilium health checks
      "4244/tcp"      # Hubble server
      "8472/udp"      # Cilium VXLAN
      "51871/udp"     # Cilium WireGuard
    )
    ;;
esac

echo "Configuring firewalld zone '${ZONE}' for role '${ROLE}' (CNI: ${CNI})..."
for port in "${PORTS[@]}"; do
  run_fw --permanent --zone="${ZONE}" --add-port="${port}"
done

# Required for pod NAT / NodePort masquerading
run_fw --permanent --zone="${ZONE}" --add-masquerade
run_fw --reload

if [[ "${DRY_RUN}" == "false" ]]; then
  echo "Active rules in zone '${ZONE}':"
  firewall-cmd --zone="${ZONE}" --list-all
fi
