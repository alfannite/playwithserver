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

| Task | Debian (`apt`) | RHEL (`dnf`) | Arch (`pacman`) | Alpine (`apk`) | openSUSE (`zypper`) |
| --- | --- | --- | --- | --- | --- |
| Refresh metadata | `apt update` | `dnf makecache` | `pacman -Sy` | `apk update` | `zypper ref` |
| Full upgrade | `apt full-upgrade` | `dnf upgrade` | `pacman -Syu` | `apk upgrade -U` | `zypper dup` / `up` |
| Install pkg | `apt install <p>` | `dnf install <p>` | `pacman -S <p>` | `apk add <p>` | `zypper in <p>` |
| Remove + deps | `apt purge <p>` | `dnf remove <p>` | `pacman -Rns <p>` | `apk del <p>` | `zypper rm -u <p>` |
| Search pkg | `apt search <q>` | `dnf search <q>` | `pacman -Ss <q>` | `apk search <q>` | `zypper se <q>` |
| Owning pkg | `dpkg -S <file>` | `rpm -qf <file>` | `pacman -Qo <f>` | `apk info -W <f>` | `rpm -qf <file>` |
| Provides bin | `apt-file search` | `dnf provides` | `pacman -F <bin>` | `apk search cmd:` | `zypper se --provides` |
| List pkg files | `dpkg -L <p>` | `rpm -ql <p>` | `pacman -Ql <p>` | `apk info -L <p>` | `rpm -ql <p>` |
| Clean cache | `apt clean` | `dnf clean all` | `paccache -r` | `apk cache clean` | `zypper clean -a` |
| Lock version | `apt-mark hold` | `dnf versionlock` | `IgnorePkg` | `apk add p=ver` | `zypper al <p>` |

> **Watch out:** Never run `pacman -Sy <pkg>` (partial upgrade) on Arch-family systems; updating the sync database without upgrading the system causes shared library mismatches and can break `pacman` or `glibc` itself. Always use `pacman -Syu <pkg>`.

## Init, Firewall, Networking, and MAC Comparison

| Subsystem | Debian / Ubuntu | RHEL / Fedora | Arch | Alpine | openSUSE |
| --- | --- | --- | --- | --- | --- |
| Init | `systemd` | `systemd` | `systemd` | `OpenRC` | `systemd` |
| Firewall | `ufw` / `nft` | `firewalld` | `nft` / `ufw` | `nft` / `awall` | `firewalld` |
| Network | `netplan` / `ifupdown2` | `NetworkManager` | `systemd-networkd` | `ifupdown-ng` | `NM` / `wicked` |
| MAC | AppArmor | SELinux | Optional | None (seccomp) | AppArmor / SELinux |
| Time sync | `chrony` / `timesyncd` | `chrony` | `timesyncd` / `chrony` | `chrony` | `chrony` |
| Auto-patch | `unattended-upgrades` | `dnf-automatic` | Manual | Image rebuild | `transactional-update` |

## Related Scripts and Universal Guides

- [scripts/linux/rocky-k8s-template.sh](../scripts/linux/rocky-k8s-template.sh) — Prepare Rocky/Alma 9 VMs for Kubernetes/K3s
- [scripts/linux/debian-base-bootstrap.sh](../scripts/linux/debian-base-bootstrap.sh) — Standard Debian/Ubuntu server baseline
- [scripts/linux/linux-sysprep-template.sh](../scripts/linux/linux-sysprep-template.sh) — Reset `machine-id`, SSH host keys, and cloud-init before VM cloning
- [scripts/linux/firewalld-k8s-ports.sh](../scripts/linux/firewalld-k8s-ports.sh) — Configure `firewalld` for control-plane or worker nodes
- [universal/cloud-init-images.md](../universal/cloud-init-images.md) — Direct official cloud-init image URLs (`.qcow2`/`.img`, no ISOs) for all major distros
- [universal/ssh-mastery.md](../universal/ssh-mastery.md) — SSH multiplexing, ProxyJump, and key management
- [universal/containers-ops.md](../universal/containers-ops.md) — Production Docker and Podman operations
