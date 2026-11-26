# Linux Administration Hub

Cross-distro reference hub and command translation table covering systemd, Debian/Ubuntu/Proxmox, RHEL/Rocky/Alma/Fedora, Arch/CachyOS, Alpine, and openSUSE/MicroOS.

[← Home](../README.md)

## Variant Guides

| Variant | Target Distributions | 01 Bootstrap | 02 Tools | 03 Tips & Tricks | 04 Hardening | 05 Troubleshooting |
| --- | --- | --- | --- | --- | --- | --- |
| `common` | Any modern Linux (systemd, LVM/ZFS, sysctl, iproute2) | [Bootstrap](common/01-bootstrap.md) | [Tools](common/02-tools.md) | [Tips & Tricks](common/03-tips-tricks.md) | [Hardening](common/04-hardening.md) | [Troubleshooting](common/05-troubleshooting.md) |
| `debian-family` | Debian 12/13, Ubuntu Server 22.04/24.04, Proxmox VE host | [Bootstrap](debian-family/01-bootstrap.md) | [Tools](debian-family/02-tools.md) | [Tips & Tricks](debian-family/03-tips-tricks.md) | [Hardening](debian-family/04-hardening.md) | [Troubleshooting](debian-family/05-troubleshooting.md) |
| `rhel-family` | Rocky 9, AlmaLinux 9, RHEL 9, Fedora Server | [Bootstrap](rhel-family/01-bootstrap.md) | [Tools](rhel-family/02-tools.md) | [Tips & Tricks](rhel-family/03-tips-tricks.md) | [Hardening](rhel-family/04-hardening.md) | [Troubleshooting](rhel-family/05-troubleshooting.md) |
| `arch-family` | Arch Linux, EndeavourOS, CachyOS | [Bootstrap](arch-family/01-bootstrap.md) | [Tools](arch-family/02-tools.md) | [Tips & Tricks](arch-family/03-tips-tricks.md) | [Hardening](arch-family/04-hardening.md) | [Troubleshooting](arch-family/05-troubleshooting.md) |
| `alpine-minimal` | Alpine Linux (VMs, routers, minimal containers) | [Bootstrap](alpine-minimal/01-bootstrap.md) | [Tools](alpine-minimal/02-tools.md) | [Tips & Tricks](alpine-minimal/03-tips-tricks.md) | [Hardening](alpine-minimal/04-hardening.md) | [Troubleshooting](alpine-minimal/05-troubleshooting.md) |
| `suse-family` | openSUSE Leap, Tumbleweed, MicroOS | [Bootstrap](suse-family/01-bootstrap.md) | [Tools](suse-family/02-tools.md) | [Tips & Tricks](suse-family/03-tips-tricks.md) | [Hardening](suse-family/04-hardening.md) | [Troubleshooting](suse-family/05-troubleshooting.md) |

## Cross-Distro Package Manager Translation

| Operation | Debian / Ubuntu (`apt`) | RHEL / Rocky / Fedora (`dnf`) | Arch (`pacman`) | Alpine (`apk`) | openSUSE (`zypper`) |
| --- | --- | --- | --- | --- | --- |
| Refresh repo metadata | `apt update` | `dnf makecache` | `pacman -Sy` | `apk update` | `zypper refresh` |
| Full system upgrade | `apt update && apt full-upgrade` | `dnf upgrade --refresh` | `pacman -Syu` | `apk upgrade -U` | `zypper dup` (TW) / `zypper up` (Leap) |
| Install package | `apt install <pkg>` | `dnf install <pkg>` | `pacman -S <pkg>` | `apk add <pkg>` | `zypper install <pkg>` |
| Remove package + unused deps | `apt purge <pkg> && apt autoremove` | `dnf remove <pkg>` | `pacman -Rns <pkg>` | `apk del <pkg>` | `zypper remove -u <pkg>` |
| Search packages | `apt search <term>` | `dnf search <term>` | `pacman -Ss <term>` | `apk search <term>` | `zypper search <term>` |
| Find which pkg owns a file | `dpkg -S /path/to/file` | `rpm -qf /path/to/file` | `pacman -Qo /path/to/file` | `apk info --who-owns /path` | `rpm -qf /path/to/file` |
| Find pkg providing unowned binary | `apt-file search bin/dig` | `dnf provides '*/dig'` | `pacman -F dig` | `apk search cmd:dig` | `zypper search --provides dig` |
| List files in installed pkg | `dpkg -L <pkg>` | `rpm -ql <pkg>` | `pacman -Ql <pkg>` | `apk info -L <pkg>` | `rpm -ql <pkg>` |
| Clean package cache | `apt clean` | `dnf clean all` | `paccache -r` | `apk cache clean` | `zypper clean --all` |
| Hold / lock package version | `apt-mark hold <pkg>` | `dnf versionlock add <pkg>` | `IgnorePkg` in `/etc/pacman.conf` | `apk add '<pkg>=<ver>'` | `zypper addlock <pkg>` |

> **Watch out:** Never run `pacman -Sy <pkg>` (partial upgrade) on Arch-family systems; updating the sync database without upgrading the system causes shared library mismatches and can break `pacman` or `glibc` itself. Always use `pacman -Syu <pkg>`.

## Init, Firewall, Networking, and MAC Comparison

| Subsystem | Debian / Ubuntu | RHEL / Rocky / Fedora | Arch | Alpine | openSUSE / MicroOS |
| --- | --- | --- | --- | --- | --- |
| Init system | `systemd` | `systemd` | `systemd` | `OpenRC` (`rc-service`, `rc-update`) | `systemd` |
| Default firewall frontend | `ufw` or `nftables` | `firewalld` (`nftables` backend) | `nftables` or `ufw` | `nftables` / `awall` | `firewalld` |
| Network stack | `netplan` (Ubuntu), `ifupdown`/`ifupdown2` (Debian/PVE) | `NetworkManager` (`nmcli`, `nmtui`) | `systemd-networkd` or `NetworkManager` | `/etc/network/interfaces` (`ifupdown-ng`) | `NetworkManager` or `wicked` (Leap) |
| MAC framework | AppArmor (`aa-status`) | SELinux (`getenforce`, `semanage`) | None by default (optional AppArmor) | None by default (grsec/seccomp in containers) | AppArmor (Leap) / SELinux (TW/MicroOS) |
| Time sync | `chrony` or `systemd-timesyncd` | `chrony` (`chronyc`) | `systemd-timesyncd` or `chrony` | `chrony` or `busybox ntpd` | `chrony` |
| Automatic updates | `unattended-upgrades` | `dnf-automatic` | Manual (never blind auto-upgrade) | Manual / immutable image rebuild | `transactional-update.timer` (MicroOS) |

## Related Scripts and Universal Guides

- [scripts/linux/rocky-k8s-template.sh](../scripts/linux/rocky-k8s-template.sh) — Prepare Rocky/Alma 9 VMs for Kubernetes/K3s
- [scripts/linux/debian-base-bootstrap.sh](../scripts/linux/debian-base-bootstrap.sh) — Standard Debian/Ubuntu server baseline
- [scripts/linux/linux-sysprep-template.sh](../scripts/linux/linux-sysprep-template.sh) — Reset `machine-id`, SSH host keys, and cloud-init before VM cloning
- [scripts/linux/firewalld-k8s-ports.sh](../scripts/linux/firewalld-k8s-ports.sh) — Configure `firewalld` for control-plane or worker nodes
- [universal/ssh-mastery.md](../universal/ssh-mastery.md) — SSH multiplexing, ProxyJump, and key management
- [universal/containers-ops.md](../universal/containers-ops.md) — Production Docker and Podman operations
