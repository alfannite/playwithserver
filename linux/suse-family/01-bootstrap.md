# openSUSE Family Bootstrap Guide

First-boot provisioning for openSUSE Leap, Tumbleweed, and MicroOS covering `zypper`, `transactional-update`, `combustion`/`ignition`, `snapper`, `chrony`, `NetworkManager`/`wicked`, and hypervisor guest agents.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Variant Comparison](#variant-comparison)
- [Verify Repositories and Initial Update](#verify-repositories-and-initial-update)
- [MicroOS Provisioning with `combustion` and `rebootmgr`](#microos-provisioning-with-combustion-and-rebootmgr)
- [Base Admin Packages and Time Sync](#base-admin-packages-and-time-sync)
- [Networking (`NetworkManager` vs `wicked`)](#networking-networkmanager-vs-wicked)
- [Admin User, SSH, and Guest Agents](#admin-user-ssh-and-guest-agents)
- [Verify Btrfs and `snapper` Snapshot Baseline](#verify-btrfs-and-snapper-snapshot-baseline)

## Variant Comparison

| Feature | openSUSE Leap | openSUSE Tumbleweed | openSUSE MicroOS |
| :--- | :--- | :--- | :--- |
| Release model | Fixed point release (SLE-aligned) | Rolling release (tested via openQA) | Immutable rolling OS (read-only `/` Btrfs) |
| Upgrade command | `zypper up` (or `zypper patch`) | `zypper dup` | `transactional-update dup` + reboot |
| Default MAC | AppArmor | SELinux (Enforcing) | SELinux (Enforcing) |
| Default network stack | `wicked` (legacy server) or `NetworkManager` | `NetworkManager` | `NetworkManager` |
| Config management | YaST + `/etc` | YaST + `/usr/etc` + `/etc` | `combustion` / `ignition` + `/etc` overlay |
| Primary workload | Traditional VMs, enterprise services | Up-to-date servers/workstations | Container hosts (Podman/K3s/RKE2), edge |

## Verify Repositories and Initial Update

### Leap and Tumbleweed `[ROOT]`

```bash
# [ROOT] Inspect enabled repositories with URIs, priorities, and refresh status
sudo zypper lr -d

# [ROOT] Refresh metadata
sudo zypper ref

# [ROOT] openSUSE Leap: apply package updates
sudo zypper up

# [ROOT] openSUSE Tumbleweed: ALWAYS use dup (distribution upgrade), never up
sudo zypper dup
```

> **Watch out:** On openSUSE Tumbleweed, running `zypper up` instead of `zypper dup` fails to resolve package splits, obsoletes, and version downgrades across rolling snapshots, gradually leaving the system in an inconsistent state. Always use `zypper dup` on Tumbleweed.

### MicroOS `[ROOT]` `[REBOOT]`

MicroOS mounts `/` read-only. All package installs and OS upgrades execute inside a new Btrfs snapshot via `transactional-update` and take effect on the next boot.

```bash
# [ROOT] Apply rolling snapshot upgrade in a new Btrfs snapshot
sudo transactional-update dup

# Inspect pending snapshot state and reboot to activate
sudo transactional-update status
sudo reboot
```

## MicroOS Provisioning with `combustion` and `rebootmgr`

MicroOS ships without a default root password or SSH keys and expects first-boot provisioning via **Combustion** (shell script executed in early boot) or **Ignition** (declarative JSON config).

### Minimal `combustion` Script Example

Place on a FAT/ext4 volume labeled `combustion` (USB stick, cloud-init ISO, or QEMU fw_cfg) at `/combustion/script`:

```bash
#!/bin/bash
# combustion: network
set -euo pipefail

# Mount /home and /var if separate subvolumes exist before creating users
mount /home || true

# Set root password hash or deploy SSH authorized key
mkdir -pm 700 /root/.ssh
echo 'ssh-ed25519 AAAA... ops@workstation' > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Create non-root wheel admin user
useradd -m -G wheel -s /bin/bash ops
mkdir -pm 700 /home/ops/.ssh
cp /root/.ssh/authorized_keys /home/ops/.ssh/authorized_keys
chown -R ops:ops /home/ops/.ssh

# Enable SSH and install qemu-guest-agent during first-boot transaction
systemctl enable sshd.service
zypper --non-interactive install --no-recommends qemu-guest-agent
systemctl enable qemu-guest-agent.service
```

### Configure `rebootmgr` Maintenance Window on MicroOS `[ROOT]`

`transactional-update.timer` automatically applies upgrades daily; control when `rebootmgr` is allowed to reboot the host:

```bash
# [ROOT] Inspect current reboot strategy
sudo rebootmgrctl status
sudo rebootmgrctl get-strategy

# Set maintenance-window strategy (only reboot between 03:00 and 04:00)
sudo rebootmgrctl set-strategy maint-window
sudo rebootmgrctl set-window 03:00 1h
sudo systemctl enable --now transactional-update.timer rebootmgr.service
```

## Base Admin Packages and Time Sync

### Install Core Utilities `[ROOT]`

Use `--no-recommends` on servers to avoid pulling desktop/printing/documentation bloat.

```bash
# [ROOT] Leap / Tumbleweed
sudo zypper in --no-recommends \
  vim tmux git curl wget ca-certificates \
  iproute2 bind-utils tcpdump mtr \
  htop btop sysstat strace lsof ncdu jq rsync \
  chrony

# [ROOT] MicroOS (keep host lean; prefer Podman/toolbox for ad-hoc tools)
sudo transactional-update pkg in --no-recommends tmux vim htop jq
```

### Enable `chrony` Time Synchronization `[ROOT]`

```bash
# [ROOT] Set UTC timezone and enable chronyd
sudo timedatectl set-timezone UTC
sudo systemctl enable --now chronyd
chronyc tracking
```

## Networking (`NetworkManager` vs `wicked`)

Verify which network daemon owns interfaces before making changes:

```bash
# [NON-ROOT] Check whether NetworkManager or wicked is active
systemctl is-active NetworkManager.service wicked.service
```

```bash
# [ROOT] NetworkManager: configure static IPv4 on eth0
sudo nmcli con mod "Wired connection 1" \
  ipv4.addresses 10.10.0.20/24 \
  ipv4.gateway 10.10.0.1 \
  ipv4.dns "1.1.1.1 9.9.9.9" \
  ipv4.method manual
sudo nmcli con up "Wired connection 1"

# [ROOT] wicked (Leap server): apply changes from /etc/sysconfig/network/ifcfg-eth0
sudo wicked ifreload eth0
sudo wicked show all
```

> **Watch out:** Never enable `wicked.service` and `NetworkManager.service` at the same time. They fight over interface state and routing tables; switch cleanly via `yast2 lan` or disable one before enabling the other.

## Admin User, SSH, and Guest Agents

### Create Non-Root Sudo User `[ROOT]`

```bash
# [ROOT] Create wheel admin user
sudo useradd -m -G wheel -s /bin/bash ops
sudo passwd ops

# Grant wheel sudo access (openSUSE ships targetpw by default in /etc/sudoers, prompting for root password)
sudo tee /etc/sudoers.d/10-wheel >/dev/null <<'EOF'
%wheel ALL=(ALL:ALL) ALL
Defaults:%wheel !targetpw
EOF
sudo chmod 0440 /etc/sudoers.d/10-wheel
sudo visudo -c
```

> **Watch out:** By default on openSUSE Leap and Tumbleweed, `/etc/sudoers` sets `Defaults targetpw`, meaning `sudo` prompts for the **root password** instead of the user's own password. Adding `Defaults:%wheel !targetpw` restores standard per-user password authentication for members of `wheel`.

### Enable SSH and Hypervisor Guest Agents `[ROOT]`

```bash
# [ROOT] Enable OpenSSH
sudo systemctl enable --now sshd

# [ROOT] KVM / QEMU / Proxmox (Leap / Tumbleweed)
sudo zypper in --no-recommends qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent

# [ROOT] VMware ESXi (Leap / Tumbleweed)
sudo zypper in --no-recommends open-vm-tools
sudo systemctl enable --now vmtoolsd
```

## Verify Btrfs and `snapper` Snapshot Baseline

openSUSE configures Btrfs with automatic `pre`/`post` `snapper` snapshots around every `zypper` and `YaST` transaction.

```bash
# [ROOT] Confirm snapper root config and baseline snapshots exist
sudo snapper list
sudo btrfs subvolume list / | head -n 20
```
