# playwithserver

Cross-platform infrastructure and systems administration field manual covering Linux, Windows, macOS, Android, universal ops tooling, and runnable bootstrap scripts.

[![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20Windows%20%7C%20macOS%20%7C%20Android-2f4f4f?style=flat-square)](#quick-jump-by-platform)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](CONTRIBUTING.md)

## Quick Jump by Platform

| Platform | Hub | Variants Covered |
| --- | --- | --- |
| Linux | [linux/README.md](linux/README.md) | Common (systemd/LVM/ZFS/sysctl), Debian/Ubuntu/Proxmox, RHEL/Rocky/Alma/Fedora, Arch/CachyOS, Alpine Minimal, openSUSE/MicroOS |
| Windows | [windows/README.md](windows/README.md) | Windows Server (OpenSSH/Hyper-V/AD/IIS/WinRM), Windows Workstation (PS7/Sysinternals/winget), WSL2 |
| macOS | [macos/README.md](macos/README.md) | System Admin (`launchd`/`pmset`/`diskutil`), Networking & Security (`pfctl`/`scutil`/SIP/FileVault), Headless Mac Server |
| Android | [android/README.md](android/README.md) | ADB & Fastboot, Termux Pocket Linux Server, Root & Shizuku Ops, Mobile Networking |
| Universal | [universal/ssh-mastery.md](universal/ssh-mastery.md) | SSH Mastery, Networking Toolkit, Containers Ops (Docker/Podman), Remote Access Mesh, [Cloud-Init OS Images](universal/cloud-init-images.md) |
| Scripts | [scripts/README.md](scripts/README.md) | Runnable bootstrap, sysprep, Kubernetes firewall, WSL2 VHDX compaction, headless Mac, and Termux/ADB scripts |

## Quick Jump by Task

| Operational Task | Direct Reference |
| --- | --- |
| Download official cloud-init VM images & install tips | [universal/cloud-init-images.md](universal/cloud-init-images.md) (Debian, Ubuntu, Rocky, Alma, Fedora, AL2023, Arch, Alpine, openSUSE, CoreOS, Flatcar, Talos, Gentoo, Kali, FreeBSD, OpenWrt) |
| Build a clean Linux VM template (K8s/Proxmox/KVM) | [linux/common/01-bootstrap.md](linux/common/01-bootstrap.md), [scripts/linux/rocky-k8s-template.sh](scripts/linux/rocky-k8s-template.sh), [scripts/linux/linux-sysprep-template.sh](scripts/linux/linux-sysprep-template.sh) |
| Identify which process owns a listening port | [linux/common/05-troubleshooting.md](linux/common/05-troubleshooting.md), [windows/windows-server/05-troubleshooting.md](windows/windows-server/05-troubleshooting.md), [macos/networking-security/02-tools.md](macos/networking-security/02-tools.md) |
| Diagnose SELinux, AppArmor, or firewalld/ufw drops | [linux/rhel-family/05-troubleshooting.md](linux/rhel-family/05-troubleshooting.md), [linux/debian-family/05-troubleshooting.md](linux/debian-family/05-troubleshooting.md), [scripts/linux/firewalld-k8s-ports.sh](scripts/linux/firewalld-k8s-ports.sh) |
| Recover full disks or compact bloated WSL2 `ext4.vhdx` | [linux/common/05-troubleshooting.md](linux/common/05-troubleshooting.md), [windows/wsl2/03-tips-tricks.md](windows/wsl2/03-tips-tricks.md), [scripts/windows/wsl2-compact-vhdx.ps1](scripts/windows/wsl2-compact-vhdx.ps1) |
| Run 24/7 low-power spare hardware (Mac Mini / Android) | [macos/mac-as-server/01-bootstrap.md](macos/mac-as-server/01-bootstrap.md), [android/termux-linux/01-bootstrap.md](android/termux-linux/01-bootstrap.md), [android/root-shizuku-ops/03-tips-tricks.md](android/root-shizuku-ops/03-tips-tricks.md) |
| Harden SSH without losing access | [universal/ssh-mastery.md](universal/ssh-mastery.md), [linux/common/04-hardening.md](linux/common/04-hardening.md), [windows/windows-server/04-hardening.md](windows/windows-server/04-hardening.md) |
| Debug TLS, DNS, latency, or packet drops | [universal/networking-toolkit.md](universal/networking-toolkit.md), [android/mobile-networking/02-tools.md](android/mobile-networking/02-tools.md) |
| Expose services securely behind CGNAT / NAT | [universal/remote-access-mesh.md](universal/remote-access-mesh.md), [android/termux-linux/03-tips-tricks.md](android/termux-linux/03-tips-tricks.md) |
| Manage Docker and Podman in production | [universal/containers-ops.md](universal/containers-ops.md), [macos/mac-as-server/02-tools.md](macos/mac-as-server/02-tools.md) |
| Recover unbootable Linux systems or roll back snapshots | [linux/arch-family/05-troubleshooting.md](linux/arch-family/05-troubleshooting.md), [linux/suse-family/05-troubleshooting.md](linux/suse-family/05-troubleshooting.md) |

## Repository Layout

Every `<platform>/<variant>/` directory follows a standardized five-file convention so operational procedures stay predictable across operating systems:

| File | Scope |
| --- | --- |
| `01-bootstrap.md` | First-boot setup, repositories, base packages, time sync, guest agents, and drivers |
| `02-tools.md` | Categorized tool matrix with exact install commands, high-signal flags, and edge cases |
| `03-tips-tricks.md` | Non-obvious sysadmin tricks, kernel/OS tuning, workflow shortcuts, and platform quirks |
| `04-hardening.md` | Production-safe security baselines that preserve Docker, Kubernetes, and SSH workflows |
| `05-troubleshooting.md` | Symptom-to-diagnostic-to-fix tables, failure workflows, and copy-paste one-liners |

```text
playwithserver/
├── README.md
├── CONTRIBUTING.md
├── LICENSE
├── linux/
│   ├── README.md
│   ├── common/                  # 01-05: systemd, journalctl, sysctl, LVM/ZFS/fstab, tmux, rsync, ss/ip
│   ├── debian-family/           # 01-05: Debian, Ubuntu Server, Proxmox host
│   ├── rhel-family/             # 01-05: Rocky, Alma, RHEL, Fedora
│   ├── arch-family/             # 01-05: Arch, EndeavourOS, CachyOS
│   ├── alpine-minimal/          # 01-05: Alpine Linux & minimal containers
│   └── suse-family/             # 01-05: openSUSE Leap/Tumbleweed, MicroOS
├── windows/
│   ├── README.md
│   ├── windows-server/          # 01-05: OpenSSH, Hyper-V, WinRM, AD/RSAT, IIS, Storage Spaces
│   ├── windows-workstation/     # 01-05: PowerShell 7, winget/scoop, Sysinternals, netsh
│   └── wsl2/                    # 01-05: .wslconfig, mirrored networking, systemd, usbipd, VHDX compact
├── macos/
│   ├── README.md
│   ├── system-admin/            # 01-05: launchd/launchctl, pmset, diskutil/APFS, tmutil, defaults
│   ├── networking-security/     # 01-05: pfctl, scutil, networksetup, SIP, Gatekeeper, FileVault
│   └── mac-as-server/           # 01-05: Headless Mac Mini 24/7, Brewfile, OrbStack/Colima, UTM
├── android/
│   ├── README.md
│   ├── adb-fastboot/            # 01-05: Wireless ADB, scrcpy, dumpsys, logcat, user-0 debloat, A/B slots
│   ├── termux-linux/            # 01-05: F-Droid Termux, openssh, proot-distro, termux-services, cloudflared
│   ├── root-shizuku-ops/        # 01-05: Shizuku, Magisk/KernelSU, ACC charge limits, iptables
│   └── mobile-networking/       # 01-05: PCAPdroid, WireGuard/Tailscale, gnirehtet, Private DNS
├── universal/
│   ├── cloud-init-images.md
│   ├── ssh-mastery.md
│   ├── networking-toolkit.md
│   ├── containers-ops.md
│   └── remote-access-mesh.md
└── scripts/
    ├── README.md
    ├── linux/
    │   ├── rocky-k8s-template.sh
    │   ├── debian-base-bootstrap.sh
    │   ├── linux-sysprep-template.sh
    │   └── firewalld-k8s-ports.sh
    ├── windows/
    │   ├── windows-ops-bootstrap.ps1
    │   └── wsl2-compact-vhdx.ps1
    ├── macos/
    │   ├── mac-headless-server.sh
    │   └── Brewfile.server
    └── android/
        ├── termux-pocket-server.sh
        └── adb-device-audit.sh
```

## Safety Tags Legend

Every operational command block and destructive procedure uses explicit inline safety tags:

| Tag | Meaning |
| --- | --- |
| `[ROOT]` | Requires `root`, `sudo`, Administrator PowerShell, or rooted Android shell (`su`) |
| `[NON-ROOT]` | Safe to run under a standard unprivileged user account |
| `[DESTRUCTIVE]` | Modifies partitions, wipes state, deletes data, drops network sessions, or revokes access—verify targets before executing |
| `[REBOOT]` | Requires a system reboot, WSL shutdown, or service restart to take full effect |

## Contributing

Contributions must follow the five-file layout, use modern non-deprecated tooling, include safety tags, and document concrete failure modes with `> **Watch out:**` callouts. See [CONTRIBUTING.md](CONTRIBUTING.md) for formatting standards and pre-PR verification commands.

## License

Released under the [MIT License](LICENSE).
