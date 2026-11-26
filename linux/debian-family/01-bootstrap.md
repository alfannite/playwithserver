# Debian, Ubuntu, and Proxmox VE Bootstrap

First-boot provisioning for Debian 12/13, Ubuntu Server 22.04/24.04 LTS, and Proxmox VE 8 hosts covering repositories, base tooling, `chrony`, `netplan`/`ifupdown2` networking, and automated security patching.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Repository Configuration](#repository-configuration)
- [Base Packages and Guest Agents](#base-packages-and-guest-agents)
- [Time Synchronization with chrony](#time-synchronization-with-chrony)
- [Networking with Netplan and ifupdown2](#networking-with-netplan-and-ifupdown2)
- [Unattended Security Updates](#unattended-security-updates)

## Repository Configuration

### Debian 12 (Bookworm) and 13 (Trixie) Backports

Debian 12+ supports the modern deb822 `.sources` format under `/etc/apt/sources.list.d/`. Adding the `backports` suite lets you install newer kernels, `zfs`, or `wireguard` selectively without upgrading the entire release.

`[ROOT]`
```bash
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

cat <<EOF > /etc/apt/sources.list.d/debian-backports.sources
Types: deb
URIs: https://deb.debian.org/debian
Suites: ${CODENAME}-backports
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

apt-get update
```

### Proxmox VE Non-Subscription Repository

Fresh Proxmox VE nodes point to the paid enterprise repositories (`pve-enterprise` and `ceph-quincy`/`ceph-reef`) and fail `apt update` with `401 Unauthorized` unless a license key is attached. Disable the enterprise files and enable `pve-no-subscription` for homelabs or non-licensed test clusters.

`[ROOT]`
```bash
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

# Disable enterprise repo entries
for f in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/ceph.list; do
  [ -f "$f" ] && sed -i 's/^deb /# deb /' "$f"
done

# Add pve-no-subscription repo
cat <<EOF > /etc/apt/sources.list.d/pve-no-subscription.list
deb http://download.proxmox.com/debian/pve ${CODENAME} pve-no-subscription
EOF

apt-get update && apt-get dist-upgrade -y
```

> **Watch out:** Never run `apt-get upgrade` alone on Proxmox VE. Proxmox kernel and cluster package transitions require `apt-get dist-upgrade` (or `apt full-upgrade`) so new kernel meta-packages and ABI dependencies install cleanly.

## Base Packages and Guest Agents

Install standard operations tooling on Debian/Ubuntu guests (skip `qemu-guest-agent` on bare-metal hosts and Proxmox hypervisors).

`[ROOT]`
```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get full-upgrade -y

apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release \
  iproute2 dnsutils tcpdump netcat-openbsd \
  rsync tmux htop ncdu jq lsof strace \
  apt-file needrestart chrony unattended-upgrades

apt-file update
```

Enable the QEMU guest agent on KVM/Proxmox VMs so the hypervisor can read guest IPs, freeze filesystems during backup snapshots, and perform clean shutdowns:

`[ROOT]`
```bash
apt-get install -y qemu-guest-agent
systemctl enable --now qemu-guest-agent
```

## Time Synchronization with chrony

Replace `systemd-timesyncd` with `chrony` for tighter clock discipline and VM drift recovery.

`[ROOT]`
```bash
systemctl disable --now systemd-timesyncd 2>/dev/null || true
systemctl enable --now chrony
chronyc tracking
chronyc sources -v
```

For isolated subnets with an internal NTP source, drop a dedicated file into `/etc/chrony/sources.d/internal.sources`:

`[ROOT]`
```bash
cat <<'EOF' > /etc/chrony/sources.d/internal.sources
server 10.10.0.10 iburst
server 10.10.0.11 iburst
EOF
systemctl reload chrony
```

## Networking with Netplan and ifupdown2

| Distribution | Primary Network Stack | Config Location | Apply Command |
| :--- | :--- | :--- | :--- |
| Ubuntu 22.04 / 24.04 | `netplan` (`systemd-networkd`) | `/etc/netplan/*.yaml` | `netplan try` / `netplan apply` |
| Debian 12 / 13 Server | `ifupdown` or `systemd-networkd` | `/etc/network/interfaces` | `systemctl reload networking` |
| Proxmox VE | `ifupdown2` | `/etc/network/interfaces` | `ifreload -a` |

### Ubuntu Netplan Static IP Example

`[ROOT]`
```bash
cat <<'EOF' > /etc/netplan/01-static.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - 10.10.20.40/24
      routes:
        - to: default
          via: 10.10.20.1
      nameservers:
        search: [internal.example.com]
        addresses: [10.10.20.10, 10.10.20.11]
EOF

chmod 0600 /etc/netplan/01-static.yaml
netplan try
```

> **Watch out:** Always run `netplan try` over SSH instead of `netplan apply`. `netplan try` automatically reverts the network configuration after 120 seconds if you lose connectivity. Also ensure permissions on `/etc/netplan/*.yaml` are `0600`, or `netplan` prints warnings and refuses sensitive fields.

### Debian and Proxmox VE Bridge with ifupdown2

On Proxmox VE (`ifupdown2`), a VLAN-aware Linux bridge allows VMs to tag traffic directly without creating separate host bridges per VLAN:

`[ROOT]`
```text
# /etc/network/interfaces
auto lo
iface lo inet loopback

iface eno1 inet manual

auto vmbr0
iface vmbr0 inet static
    address 10.10.10.5/24
    gateway 10.10.10.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

Apply live without dropping unrelated interfaces:

`[ROOT]`
```bash
ifreload -a
```

## Unattended Security Updates

Enable automatic security patches while preventing surprise mid-day reboots by restricting automatic reboots to a maintenance window (or leaving reboots manual and alerting via `/var/run/reboot-required`).

`[ROOT]`
```bash
cat <<'EOF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat <<'EOF' > /etc/apt/apt.conf.d/51-local-unattended
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

unattended-upgrade --dry-run --debug | tail -n 30
```
