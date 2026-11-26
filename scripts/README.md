# Automation Scripts Index

Production-ready, idempotent-where-possible shell and PowerShell scripts referenced across the platform guides.

[← Home](../README.md)

## Script Inventory

| Script | Target OS | Safety Tags | Purpose |
| --- | --- | --- | --- |
| [linux/rocky-k8s-template.sh](linux/rocky-k8s-template.sh) | Rocky Linux 9 / AlmaLinux 9 / RHEL 9 | `[ROOT]` `[REBOOT]` | Installs EPEL + sysadmin tools + `qemu-guest-agent`, disables swap, loads `overlay`/`br_netfilter`, configures K8s `sysctl`, sets SELinux permissive |
| [linux/debian-base-bootstrap.sh](linux/debian-base-bootstrap.sh) | Debian 12+ / Ubuntu 22.04+ | `[ROOT]` | Updates apt, installs core ops utilities, configures `chrony` and `unattended-upgrades`, applies safe `sysctl` baseline |
| [linux/linux-sysprep-template.sh](linux/linux-sysprep-template.sh) | Debian / Ubuntu / RHEL / Rocky VMs | `[ROOT]` `[DESTRUCTIVE]` `[REBOOT]` | Resets `/etc/machine-id`, removes SSH host keys, cleans `cloud-init`, truncates logs, clears bash history before converting VM to template |
| [linux/firewalld-k8s-ports.sh](linux/firewalld-k8s-ports.sh) | Rocky / Alma / RHEL / Fedora / openSUSE | `[ROOT]` | Opens required Kubernetes/K3s firewalld ports using `--role control-plane` or `--role worker` |
| [windows/windows-ops-bootstrap.ps1](windows/windows-ops-bootstrap.ps1) | Windows 10/11 / Server with `winget` | `[NON-ROOT]` / `[ROOT]` | Installs PowerShell 7, Git, Windows Terminal, Sysinternals, and essential CLI tools via `winget` |
| [windows/wsl2-compact-vhdx.ps1](windows/wsl2-compact-vhdx.ps1) | Windows 10/11 with WSL2 | `[ROOT]` `[DESTRUCTIVE]` | Shuts down all WSL instances cleanly and compacts one or all `ext4.vhdx` virtual disks via `Optimize-VHD` or `diskpart` |
| [macos/mac-headless-server.sh](macos/mac-headless-server.sh) | macOS 13+ (Apple Silicon & Intel) | `[ROOT]` | Configures `pmset` for 24/7 headless server operation, enables SSH (Remote Login), and applies `Brewfile.server` |
| [macos/Brewfile.server](macos/Brewfile.server) | macOS with Homebrew | `[NON-ROOT]` | Curated Homebrew bundle for server/ops Macs (modern CLI tools, networking, container runtimes) |
| [android/termux-pocket-server.sh](android/termux-pocket-server.sh) | Android Termux (F-Droid build) | `[NON-ROOT]` | Bootstraps Termux with `openssh`, `tmux`, `termux-services`, wake-lock, boot hook, and core CLI utilities |
| [android/adb-device-audit.sh](android/adb-device-audit.sh) | Linux / macOS / Git Bash host with `adb` | `[NON-ROOT]` | Collects battery health, thermals, storage usage, IP/network state, and top services from an ADB-connected Android device |

## Quick Usage Examples

### Linux

`[ROOT]`
```bash
# Prepare a Rocky 9 Kubernetes node template
sudo ./scripts/linux/rocky-k8s-template.sh

# Open K8s firewalld ports for a control-plane or worker node
sudo ./scripts/linux/firewalld-k8s-ports.sh --role control-plane
sudo ./scripts/linux/firewalld-k8s-ports.sh --role worker

# Bootstrap a fresh Debian or Ubuntu server
sudo ./scripts/linux/debian-base-bootstrap.sh

# Clean a VM right before powering off to save as a Proxmox/KVM template
sudo ./scripts/linux/linux-sysprep-template.sh --confirm
```

### Windows (PowerShell)

`[ROOT]`
```powershell
# Bootstrap workstation tools via winget
.\scripts\windows\windows-ops-bootstrap.ps1

# Compact all WSL2 ext4.vhdx disks (stops running WSL instances)
.\scripts\windows\wsl2-compact-vhdx.ps1 -All
```

### macOS

`[ROOT]`
```bash
# Configure 24/7 headless Mac Mini power settings, SSH, and Brewfile tools
sudo ./scripts/macos/mac-headless-server.sh

# Or apply only the Brewfile as your regular user
brew bundle --file=./scripts/macos/Brewfile.server
```

### Android

`[NON-ROOT]`
```bash
# Inside Termux on the Android device
./scripts/android/termux-pocket-server.sh

# From a workstation connected to an Android device over USB or Wireless ADB
./scripts/android/adb-device-audit.sh
./scripts/android/adb-device-audit.sh -s 192.168.1.50:5555
```

> **Watch out:** Inspect every script before executing it on a production host. `linux-sysprep-template.sh` deletes SSH host keys and resets `/etc/machine-id`—running it on a live production server rather than a template VM will break SSH host trust and DHCP client leases until regenerated.
