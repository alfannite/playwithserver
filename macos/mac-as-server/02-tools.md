# Headless Mac Server Tools

Operational toolset for running Docker, Kubernetes, Linux/macOS VMs, remote access, storage monitoring, and declarative provisioning on a 24/7 Mac Mini server.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Tools Quick Matrix](#tools-quick-matrix)
- [OrbStack (Containers, Kubernetes, and Linux Machines)](#orbstack-containers-kubernetes-and-linux-machines)
- [Colima (Open-Source Headless Docker/K8s Runtime)](#colima-open-source-headless-dockerk8s-runtime)
- [Lima and Tart (Apple Virtualization Framework VMs)](#lima-and-tart-apple-virtualization-framework-vms)
- [UTM and utmctl (Full GUI and Headless Virtualization)](#utm-and-utmctl-full-gui-and-headless-virtualization)
- [brew bundle and brew services](#brew-bundle-and-brew-services)
- [smartmontools and iperf3 (NVMe Health and Throughput)](#smartmontools-and-iperf3-nvme-health-and-throughput)
- [Tailscale Daemon (Headless Mesh VPN)](#tailscale-daemon-headless-mesh-vpn)

## Tools Quick Matrix

| Tool | Install Command | Domain | Best Fit on Mac Server |
| :--- | :--- | :--- | :--- |
| `OrbStack` (`orb`) | `brew install --cask orbstack` | Containers / Linux VMs | Lowest idle RAM/CPU, fast VirtioFS, built-in `*.orb.local` DNS |
| `Colima` | `brew install colima docker` | Containers / K8s | Pure CLI, open-source, runs cleanly as a `launchd` background service |
| `Lima` (`limactl`) | `brew install lima` | Linux VMs (VZ/QEMU) | Custom cloud-init Linux VMs on Apple Virtualization Framework |
| `Tart` | `brew install cirruslabs/cli/tart` | macOS & Linux VMs | CI/CD macOS runner VMs pushed/pulled via OCI container registries |
| `UTM` (`utmctl`) | `brew install --cask utm` | Mixed VMs (VZ + QEMU) | Running x86_64/ARM64 OSes with headless `utmctl` automation |
| `brew bundle` | Built into Homebrew | Provisioning | Declarative `Brewfile` export, install, and drift check |
| `smartctl` | `brew install smartmontools` | Storage Health | SMART wear, temperature, and error inspection for internal & Thunderbolt NVMe |
| `tailscaled` | `brew install tailscale` | Zero-Trust VPN | Boot-time remote SSH & Screen Sharing access without port forwarding |

## OrbStack (Containers, Kubernetes, and Linux Machines)

**Install:** `brew install --cask orbstack`

### High-Signal Usages `[NON-ROOT]`

```bash
# Inspect status, resource caps, and active Linux/Docker runtime
orb status
orb config show

# Cap CPU and RAM so containers cannot starve macOS host services
orb config set cpu 6
orb config set memory_mib 12288

# Launch a lightweight Debian or Ubuntu Linux VM alongside Docker containers
orb create ubuntu:24.04 infra-vm
orb run -m infra-vm uname -a

# Start or stop OrbStack cleanly from SSH
orb start
orb stop
```

> **Watch out:** OrbStack runs inside a user session (`gui/<uid>`), not as a root `LaunchDaemon`. On a headless Mac Mini after an unattended reboot, OrbStack will not auto-start until the user session logs in—either pair with a non-FileVault auto-login + screen lock strategy or use a `LaunchDaemon`-managed service if containers must start before GUI login.

## Colima (Open-Source Headless Docker/K8s Runtime)

**Install:** `brew install colima docker docker-compose docker-buildx`

### High-Signal Usages `[NON-ROOT]`

```bash
# Start a high-performance Apple Virtualization Framework (vz) + VirtioFS Docker VM with Rosetta x86_64 support
colima start \
  --cpu 4 --memory 8 --disk 100 \
  --vm-type vz --vz-rosetta --mount-type virtiofs \
  --network-address

# Start a named profile with built-in k3s Kubernetes cluster
colima start --profile k8s --kubernetes --cpu 4 --memory 8 --vm-type vz

# Inspect VM IP, disk usage, and SSH directly into the Linux VM
colima list
colima ssh -- df -h

# Run Colima automatically via Homebrew launchd agent
brew services start colima
```

### OrbStack vs Colima Decision Matrix

| Criteria | OrbStack | Colima |
| :--- | :--- | :--- |
| License | Free for personal/homelab; commercial license for business | 100% MIT open-source |
| Idle RAM / CPU | Very low (~200–400 MB dynamic memory ballooning) | Fixed VM allocation (`--memory`) |
| File I/O Speed | Excellent (custom VirtioFS + caching) | Fast (`--vm-type vz --mount-type virtiofs`) |
| Headless Automation | Good via `orb` CLI (requires user GUI session) | Excellent pure CLI + `brew services` |
| Docker Desktop Parity | Drop-in socket, `.orb.local` domains, K8s toggle | Drop-in Docker/containerd/k3s via Lima |

> **Watch out:** Colima defaults to QEMU (`--vm-type qemu`) and `sshfs` on older configs, which delivers poor disk I/O. Always specify `--vm-type vz --mount-type virtiofs` on macOS 13+ Apple Silicon hosts for near-native container bind-mount performance.

## Lima and Tart (Apple Virtualization Framework VMs)

**Install:** `brew install lima` and `brew install cirruslabs/cli/tart`

### High-Signal Usages `[NON-ROOT]`

```bash
# Lima: create and start a custom Debian VM using Apple VZ
limactl create --name=srv-debian --vm-type=vz --cpus=2 --memory=4 --disk=40 template://debian
limactl start srv-debian
limactl shell srv-debian

# Tart: pull a prebuilt macOS Sequoia VM from GitHub Container Registry and run headless
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest ci-runner
tart set ci-runner --cpu 4 --memory 8192
tart run --no-graphics ci-runner &

# Retrieve the running Tart VM IP address for SSH automation
tart ip ci-runner
```

> **Watch out:** Apple's macOS EULA and Virtualization.framework enforce a hard limit of **2 concurrent macOS guest VMs** per physical Apple Silicon Mac host (`VZErrorVirtualMachineLimitExceeded`). Linux guest VMs running on Virtualization.framework have no such 2-VM cap.

## UTM and utmctl (Full GUI and Headless Virtualization)

**Install:** `brew install --cask utm`

### High-Signal Usages `[NON-ROOT]`

```bash
# Add utmctl to PATH (bundled inside UTM.app)
export PATH="/Applications/UTM.app/Contents/MacOS:$PATH"

# List configured VMs with UUID and state
utmctl list

# Start, query IP, and gracefully shut down a VM headless over SSH
utmctl start "Ubuntu-Server"
utmctl ip-address "Ubuntu-Server"
utmctl stop "Ubuntu-Server"
```

> **Watch out:** `utmctl` communicates with the running `UTM.app` GUI process over Apple Events/XPC. On a completely headless Mac without an active user GUI session (or where `UTM.app` is closed), `utmctl` cannot start VMs. Use `lima` or `tart` for strictly headless CLI-only VM orchestration.

## brew bundle and brew services

**Install:** Built into Homebrew (`/opt/homebrew/bin/brew`).

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Dump current server package inventory cleanly
brew bundle dump --describe --force --file=~/Brewfile

# Prune packages not declared in Brewfile (preview first without --force)
brew bundle cleanup --file=~/Brewfile

# Run a Homebrew service as a system LaunchDaemon (starts at boot before login)
sudo brew services start caddy
sudo brew services list
```

> **Watch out:** Running `sudo brew services start <formula>` places the plist in `/Library/LaunchDaemons/` and runs the service as `root` unless the formula defines a `UserName`. Running `brew services start <formula>` *without* `sudo` places it in `~/Library/LaunchAgents/`, which will **not** start after a headless reboot until that user logs in.

## smartmontools and iperf3 (NVMe Health and Throughput)

**Install:** `brew install smartmontools iperf3`

### High-Signal Usages `[ROOT]` / `[NON-ROOT]`

```bash
# Inspect internal Apple SSD wear level (Percentage Used), temperature, and media errors
sudo smartctl -a /dev/disk0 | grep -E "Temperature|Percentage Used|Data Units Written|Media and Data"

# Inspect an external Thunderbolt NVMe enclosure (pass-through requires Thunderbolt/USB4; many USB-SATA bridges block SMART)
sudo smartctl -a /dev/disk4

# Run a 10GbE LAN throughput benchmark server on the Mac Mini
iperf3 -s -B 192.168.10.50
```

> **Watch out:** Cheap USB 3.2 Gen 2 NVMe enclosures (Realtek RTL9210 / JMicron JMS583) frequently block NVMe SMART pass-through and suffer silent bus resets under sustained I/O. Use native Thunderbolt 3/4 or ASM2464PD USB4 enclosures for 24/7 external server storage.

## Tailscale Daemon (Headless Mesh VPN)

**Install:** `brew install tailscale`

### High-Signal Usages `[ROOT]`

```bash
# Start tailscaled as a boot-time root LaunchDaemon
sudo brew services start tailscale

# Join tailnet as a subnet router without overriding local server DNS
sudo tailscale up --advertise-routes=192.168.10.0/24 --accept-dns=false

# Check direct peer-to-peer vs DERP relay connection status
tailscale status
tailscale ping admin-laptop
```

> **Watch out:** Do not run the Mac App Store `Tailscale.app` and Homebrew `tailscaled` simultaneously—they conflict on `utun` interfaces and state sockets. For headless 24/7 servers, remove the GUI app and run solely the `tailscaled` system daemon via `sudo brew services start tailscale` or the official standalone macOS `tailscaled` system package.
