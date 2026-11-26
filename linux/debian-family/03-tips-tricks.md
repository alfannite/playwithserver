# Debian, Ubuntu, and Proxmox VE Tips and Tricks

Practical administration tricks for APT pinning, Debian backports, Proxmox VLAN bridges, `needrestart` automation control, and fast package diagnostics.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Package Pinning, Holds, and Backports](#package-pinning-holds-and-backports)
- [Netplan and Proxmox VLAN Bridges](#netplan-and-proxmox-vlan-bridges)
- [Fast APT and DPKG Workflows](#fast-apt-and-dpkg-workflows)
- [Proxmox VE Host Optimizations](#proxmox-ve-host-optimizations)
- [Controlling needrestart and Cloud-Init](#controlling-needrestart-and-cloud-init)

## Package Pinning, Holds, and Backports

### Pin a Single Backports Package Without Upgrading Everything

Debian backports defaults to pin priority `100`, meaning packages are never pulled automatically unless requested. To keep a single package (such as `linux-image-amd64` or `btrfs-progs`) continuously updated from backports while holding the rest of the OS on stable, add a targeted preferences file:

`[ROOT]`
```bash
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

cat <<EOF > /etc/apt/preferences.d/90-backports-kernel.pref
Package: linux-image-amd64 linux-headers-amd64
Pin: release a=${CODENAME}-backports
Pin-Priority: 500
EOF

apt-cache policy linux-image-amd64
```

### Safe Config File Handling During Non-Interactive Upgrades

When upgrading headless servers via Ansible or CI, prevent `dpkg` from hanging on modified config prompts while preserving your customized `/etc/` files:

`[ROOT]`
```bash
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"
```

After patching, locate any `.dpkg-dist` or `.dpkg-new` files left by upgraded packages and merge upstream changes intentionally:

`[ROOT]`
```bash
find /etc -name '*.dpkg-*' -o -name '*.ucf-*'
```

## Netplan and Proxmox VLAN Bridges

### VLAN Sub-Interface on Ubuntu Netplan

Tag a trunk interface (`ens18`) for an isolated storage VLAN (`vlan.120`) without taking down management connectivity:

`[ROOT]`
```yaml
# /etc/netplan/20-storage-vlan.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      dhcp4: false
  vlans:
    vlan120:
      id: 120
      link: ens18
      mtu: 9000
      addresses:
        - 10.120.0.15/24
```

Validate and test with automatic rollback:

`[ROOT]`
```bash
chmod 0600 /etc/netplan/20-storage-vlan.yaml
netplan try
```

### Proxmox VE Bonded LACP Trunk + VLAN-Aware Bridge

Combine two NICs into an 802.3ad (`LACP`) bond carrying a management VLAN (`vmbr0.10`) while allowing guest VMs to tag arbitrary VLAN IDs:

`[ROOT]`
```text
# /etc/network/interfaces
auto eno1
iface eno1 inet manual

auto eno2
iface eno2 inet manual

auto bond0
iface bond0 inet manual
    bond-slaves eno1 eno2
    bond-miimon 100
    bond-mode 802.3ad
    bond-xmit-hash-policy layer3+4

auto vmbr0
iface vmbr0 inet manual
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094

auto vmbr0.10
iface vmbr0.10 inet static
    address 10.10.10.5/24
    gateway 10.10.10.1
```

> **Watch out:** Changing the management IP from `vmbr0` to `vmbr0.10` requires the upstream switch port to deliver VLAN 10 tagged (trunk mode) rather than untagged (access mode). Always have out-of-band IPMI/iDRAC/iLO console access ready before running `ifreload -a` on a hypervisor trunk change.

## Fast APT and DPKG Workflows

### Keep Minimal Hosts Lean by Skipping Recommended Bloat

By default, APT installs `Recommends` packages (often pulling X11 libraries or docs onto headless servers). Keep image footprints small globally or per-command:

`[ROOT]`
```bash
cat <<'EOF' > /etc/apt/apt.conf.d/99-norecommends
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
```

### Audit Manually Installed Packages and Pending Reboots

```bash
# List packages explicitly installed (excluding base/priority required) [NON-ROOT]
comm -23 <(apt-mark showmanual | sort) <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | sed -n 's/^Package: //p' | sort)

# Check if a kernel or glibc update requires a reboot [NON-ROOT]
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required /var/run/reboot-required.pkgs || echo "No reboot required"

# Verify whether package files on disk were modified from maintainer checksums [ROOT]
dpkg --verify
```

## Proxmox VE Host Optimizations

### Reduce Disk Wear on Consumer SSDs and NVMe Boot Drives

Proxmox cluster services (`pve-ha-lrm`, `pve-ha-crm`, `corosync`) write telemetry to `/var/lib/rrdcached` and `/etc/pve` continuously. On single-node standalone hosts (not part of a cluster), disabling HA daemons removes unnecessary write amplification:

`[ROOT]`
```bash
# Standalone single-node Proxmox hosts ONLY (do not run on clustered nodes)
systemctl disable --now pve-ha-lrm pve-ha-crm corosync
```

### Enable IOMMU and Trim Discards for Guest Disks

Verify periodic `fstrim` is active for SSD/NVMe thin storage and enable guest TRIM (`discard=on`) on VM SCSI disks:

`[ROOT]`
```bash
systemctl enable --now fstrim.timer
systemctl status fstrim.timer --no-pager
```

> **Watch out:** Never disable `corosync` on a multi-node Proxmox cluster, even temporarily for maintenance; losing quorum puts `/etc/pve` (`pmxcfs`) into read-only mode across the cluster and blocks VM starts and config edits.

## Controlling needrestart and Cloud-Init

### Configure needrestart for Headless Production Servers

Set `needrestart` to list-only mode during automated runs or exclude stateful engines (PostgreSQL, Docker, Containerd) from automatic restarts:

`[ROOT]`
```bash
cat <<'EOF' > /etc/needrestart/conf.d/90-local.conf
# 'l' = list only, 'a' = auto-restart, 'i' = interactive
$nrconf{restart} = 'l';
# Keep databases and container runtimes out of automatic restarts if switched to 'a'
$nrconf{override_rc}{qr/^docker\.service/} = 0;
$nrconf{override_rc}{qr/^containerd\.service/} = 0;
$nrconf{override_rc}{qr/^postgresql/} = 0;
EOF
```

### Prevent Cloud-Init from Overwriting Static Netplan Configs

On Ubuntu cloud images (Proxmox cloud-init templates, AWS, Hetzner), disable cloud-init network regeneration once you take manual control of `/etc/netplan/`:

`[ROOT]`
```bash
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```
