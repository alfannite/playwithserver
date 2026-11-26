# Rocky, AlmaLinux, RHEL 9, and Fedora Bootstrap

First-boot provisioning for Enterprise Linux 9 (Rocky 9, AlmaLinux 9, RHEL 9) and Fedora Server covering EPEL/CRB repositories, base utilities, `nmcli` networking, `tuned`, `cockpit`, and `dnf-automatic`.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Repositories, EPEL, and CRB](#repositories-epel-and-crb)
- [Base Packages and Guest Agent](#base-packages-and-guest-agent)
- [Networking with NetworkManager and nmcli](#networking-with-networkmanager-and-nmcli)
- [Performance Profiles with tuned](#performance-profiles-with-tuned)
- [Cockpit Web Console and Automatic Updates](#cockpit-web-console-and-automatic-updates)

## Repositories, EPEL, and CRB

On Rocky Linux 9 and AlmaLinux 9, enable the **CRB** (CodeReady Builder) repository before installing **EPEL**, because many EPEL packages depend on libraries hosted in CRB. (Skip this section on Fedora Server, which already ships up-to-date packages in its default repos.)

`[ROOT]`
```bash
# Rocky Linux 9 / AlmaLinux 9
dnf install -y dnf-plugins-core
dnf config-manager --set-enabled crb
dnf install -y epel-release

# RHEL 9 (requires active subscription-manager registration)
# subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms"
# dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

dnf makecache
dnf repolist enabled
```

> **Watch out:** On RHEL 9, `dnf config-manager --set-enabled crb` will not work unless the repository ID matches `codeready-builder-for-rhel-9-x86_64-rpms` (or `aarch64`). Use `subscription-manager repos --list-enabled` on RHEL hosts rather than guessing repo IDs.

## Base Packages and Guest Agent

Upgrade base packages and install essential admin, SELinux policy management, and DNF plugin packages:

`[ROOT]`
```bash
dnf upgrade -y

dnf install -y \
  dnf-utils python3-dnf-plugin-versionlock \
  policycoreutils-python-utils setroubleshoot-server \
  bind-utils iproute tcpdump nmap-ncat \
  rsync tmux btop ncdu jq lsof strace tar \
  chrony tuned
```

Enable time synchronization and the QEMU guest agent (on KVM/Proxmox VMs):

`[ROOT]`
```bash
systemctl enable --now chronyd
chronyc tracking

# KVM / Proxmox / OpenStack VM guests only
dnf install -y qemu-guest-agent
systemctl enable --now qemu-guest-agent
```

## Networking with NetworkManager and nmcli

EL 9 and Fedora Server use **NetworkManager** with keyfile profiles stored under `/etc/NetworkManager/system-connections/` (replacing legacy `/etc/sysconfig/network-scripts/ifcfg-*`).

Inspect active devices and connections:

`[NON-ROOT]`
```bash
nmcli device status
nmcli connection show
```

Configure a static IPv4 address, gateway, and DNS on an existing profile (`ens18`):

`[ROOT]`
```bash
nmcli connection modify ens18 \
  ipv4.method manual \
  ipv4.addresses 10.10.20.45/24 \
  ipv4.gateway 10.10.20.1 \
  ipv4.dns "10.10.20.10 10.10.20.11" \
  ipv4.dns-search "internal.example.com" \
  connection.autoconnect yes

nmcli connection up ens18
```

> **Watch out:** Changing an IP address via `nmcli connection up` over SSH immediately terminates your session if the new address differs from the old one. For remote IP migrations, add the new IP alongside the old one (`+ipv4.addresses`), reconnect on the new IP, and then remove the old address (`-ipv4.addresses`), or schedule an `at` rollback command.

## Performance Profiles with tuned

`tuned` applies coordinated kernel `sysctl`, scheduler, and block-layer parameters tailored to hardware or VM workloads.

| Profile | Best Workload |
| :--- | :--- |
| `virtual-guest` | Default for KVM/VMware/Cloud VMs |
| `throughput-performance` | Bare-metal storage, web, and database servers |
| `network-latency` | Low-latency proxies, trading, and real-time UDP |
| `virtual-host` | KVM hypervisor hosts |

`[ROOT]`
```bash
systemctl enable --now tuned
tuned-adm recommend
tuned-adm profile virtual-guest
tuned-adm active
```

## Cockpit Web Console and Automatic Updates

### Cockpit Web Management (Optional)

Cockpit runs on demand via socket activation (zero idle RAM footprint when unused) on TCP port `9090`.

`[ROOT]`
```bash
dnf install -y cockpit cockpit-storaged cockpit-podman
systemctl enable --now cockpit.socket

# Restrict port 9090 to your management subnet in firewalld
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.10.0.0/16" service name="cockpit" accept'
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --reload
```

### Automated Security Patching with dnf-automatic

Install and configure `dnf-automatic` to apply security advisories automatically without forced reboots:

`[ROOT]`
```bash
dnf install -y dnf-automatic

cat <<'EOF' > /etc/dnf/automatic.conf
[commands]
upgrade_type = security
random_sleep = 300
download_updates = yes
apply_updates = yes
reboot = never

[emitters]
emit_via = stdio

[base]
debuglevel = 1
EOF

systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer
```
