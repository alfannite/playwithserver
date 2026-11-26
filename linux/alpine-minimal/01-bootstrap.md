# Alpine Linux Bootstrap Guide

First-boot provisioning for Alpine Linux VMs, edge routers, diskless RAM hosts, and minimal OCI containers covering `setup-alpine`, `apk` repositories, `doas`, OpenRC, `chrony`, and `lbu`.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Alpine Deployment Modes](#alpine-deployment-modes)
- [Initial System Setup (`setup-alpine`)](#initial-system-setup-setup-alpine)
- [Configure `apk` Repositories and Upgrade](#configure-apk-repositories-and-upgrade)
- [Admin User and `doas` Privilege Escalation](#admin-user-and-doas-privilege-escalation)
- [Timezone, `chrony` NTP, and Base Admin Packages](#timezone-chrony-ntp-and-base-admin-packages)
- [OpenRC Services and Hypervisor Guest Agents](#openrc-services-and-hypervisor-guest-agents)
- [Diskless Mode Persistence with `lbu`](#diskless-mode-persistence-with-lbu)

## Alpine Deployment Modes

| Mode | Root Filesystem | Persistence Mechanism | Primary Use Case |
| :--- | :--- | :--- | :--- |
| `sys` | Traditional ext4/XFS/Btrfs on disk | Direct writes to disk | Standard servers, VMs, Docker hosts |
| `diskless` | `tmpfs` in RAM | `lbu commit` saves `/etc` overlay (`.apkovl.tar.gz`) to USB/SD/disk | Routers, firewalls, Raspberry Pi, edge appliances |
| `data` | `tmpfs` in RAM + `/var` on disk | `lbu` for `/etc` + persistent `/var` partition | High-write edge hosts needing immutable OS + durable logs/DB |
| Container (OCI) | OverlayFS layer | Stateless image (`Dockerfile`) | Microservices, CI runners, minimal base images |

## Initial System Setup (`setup-alpine`)

On a fresh ISO or bare VM console, run `setup-alpine` to configure keyboard, hostname, interfaces, timezone, NTP, mirrors, SSH, and disk mode in one guided pass:

```sh
# [ROOT] Interactive full bootstrap
setup-alpine
```

For scripted or incremental adjustments after initial install, invoke the modular `alpine-conf` scripts directly:

```sh
# [ROOT] Reconfigure individual subsystems independently
setup-hostname -n edge-gw-01 && hostname -F /etc/hostname
setup-interfaces -a
setup-timezone -z UTC
setup-ntp -c chrony
setup-sshd -c openssh
```

## Configure `apk` Repositories and Upgrade

By default, fresh installs often have the `community` repository commented out in `/etc/apk/repositories`. Most server tooling (`doas`, `btop`, `docker`, `qemu-guest-agent`, `awall`, `jq`) lives in `community`.

```sh
# [ROOT] Inspect active repositories
cat /etc/apk/repositories

# [ROOT] Uncomment the community repository matching the current release
sed -i '/\/community$/s/^#//' /etc/apk/repositories

# Verify main + community are active (example for v3.21)
# https://dl-cdn.alpinelinux.org/alpine/v3.21/main
# https://dl-cdn.alpinelinux.org/alpine/v3.21/community

# [ROOT] Sync package index and apply all updates
apk update
apk upgrade --available
```

> **Watch out:** Never mix `edge/main` into a stable release's `/etc/apk/repositories` untagged. Doing so silently upgrades `musl`, `busybox`, and `openssl` to rolling edge snapshots. Always use repository tags (`@testing`) if you need a single package from `edge/testing`.

## Admin User and `doas` Privilege Escalation

Alpine prefers OpenBSD's minimal `doas` over `sudo`.

```sh
# [ROOT] Install doas and shadow utilities if needed
apk add doas

# [ROOT] Create non-root admin user and add to wheel group
adduser -g "Operations Admin" ops
addgroup ops wheel

# [ROOT] Configure doas drop-in rule (persist caches auth for 5 minutes)
mkdir -p /etc/doas.d
cat <<'EOF' > /etc/doas.d/20-wheel.conf
permit persist :wheel
EOF
chmod 0640 /etc/doas.d/20-wheel.conf

# Validate config syntax before testing
doas -C /etc/doas.d/20-wheel.conf && echo "doas config OK"
```

> **Watch out:** `doas` requires a trailing newline at the end of every rule file and rejects files with syntax errors completely. Always validate with `doas -C /etc/doas.d/20-wheel.conf` before logging out of `root`.

## Timezone, `chrony` NTP, and Base Admin Packages

### Install Timezone Data and `chrony` `[ROOT]`

Alpine containers and minimal installs omit `/usr/share/zoneinfo` unless `tzdata` is installed.

```sh
# [ROOT] Install timezone database and chrony
apk add tzdata chrony

# Set UTC (or replace with e.g. America/New_York)
cp /usr/share/zoneinfo/UTC /etc/localtime
echo "UTC" > /etc/timezone

# Enable and start chronyd
rc-update add chronyd default
rc-service chronyd start
chronyc tracking
```

### Install Core Server Diagnostics `[ROOT]`

Alpine ships BusyBox minimal applets by default; install full network and diagnostic tools for production troubleshooting.

```sh
# [ROOT] Core CLI utilities for VM/server administration
apk add \
  openssh curl wget ca-certificates \
  iproute2 iproute2-ss bind-tools tcpdump mtr \
  vim tmux git htop btop lsof strace ncdu jq rsync \
  util-linux pciutils usbutils
```

## OpenRC Services and Hypervisor Guest Agents

### Verify Base Runlevels `[ROOT]`

```sh
# [ROOT] Inspect active runlevel and running daemons
rc-status -a

# Enable OpenSSH at default runlevel
rc-update add sshd default
rc-service sshd start
```

### Install Hypervisor Guest Agents `[ROOT]`

```sh
# [ROOT] KVM / QEMU / Proxmox
apk add qemu-guest-agent
rc-update add qemu-guest-agent default
rc-service qemu-guest-agent start

# [ROOT] VMware ESXi
apk add open-vm-tools open-vm-tools-guestinfo
rc-update add open-vm-tools default
rc-service open-vm-tools start
```

## Diskless Mode Persistence with `lbu`

If Alpine was installed in `diskless` or `data` mode, all root filesystem changes live in RAM (`tmpfs`) and vanish on reboot until committed with `lbu` (Alpine Local Backup).

```sh
# [ROOT] Review modified files pending backup (tracks /etc and /etc/apk/world by default)
lbu status

# Include additional custom paths outside /etc (e.g., admin SSH keys in /home/ops)
lbu include /home/ops/.ssh

# Review line-by-line diff against last saved overlay
lbu diff

# Commit changes to persistent storage (.apkovl.tar.gz)
lbu commit -d
```
