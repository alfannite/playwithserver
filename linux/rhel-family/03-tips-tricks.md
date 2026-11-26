# Rocky, AlmaLinux, RHEL 9, and Fedora Tips and Tricks

High-leverage admin workflows for speeding up `dnf`, rolling back updates, mastering SELinux labeling, configuring `firewalld` policies for containers, and building custom `tuned` profiles.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [DNF Speed, History Rollback, and Version Locks](#dnf-speed-history-rollback-and-version-locks)
- [SELinux Operational Shortcuts](#selinux-operational-shortcuts)
- [firewalld Policies and Container Zones](#firewalld-policies-and-container-zones)
- [NetworkManager Multi-Homed and VLAN Tricks](#networkmanager-multi-homed-and-vlan-tricks)
- [Custom tuned Profiles and Cockpit Extensions](#custom-tuned-profiles-and-cockpit-extensions)

## DNF Speed, History Rollback, and Version Locks

### Parallel Downloads and Fastest Mirror

Add parallel downloads and clean kernel retention to `/etc/dnf/dnf.conf` to speed up patching across fleets:

`[ROOT]`
```ini
# Append under [main] in /etc/dnf/dnf.conf
max_parallel_downloads=10
fastestmirror=True
installonly_limit=3
defaultyes=False
```

### Roll Back a Bad Package Transaction

Every `dnf` install, upgrade, or removal is logged as a numbered transaction. Inspect the exact diff and roll back if a package update introduces a regression:

`[ROOT]`
```bash
dnf history list | head -n 15
dnf history info 24
dnf history undo 24
```

### Download RPMs Offline Without Installing

Useful for air-gapped environments or inspecting package scripts prior to rollout:

`[NON-ROOT]`
```bash
dnf download --resolve --destdir=/tmp/rpms nginx
```

## SELinux Operational Shortcuts

### Use Per-Domain Permissive Mode Instead of `setenforce 0`

Never drop the entire host to `Permissive` (`setenforce 0`) just to debug one daemon. Put only the single SELinux domain (for example, `httpd_t`) into permissive mode so every other service stays protected while denials are logged:

`[ROOT]`
```bash
# Make only httpd_t permissive during troubleshooting
semanage permissive -a httpd_t

# List active per-domain permissive overrides
semanage permissive -l

# Re-enforce httpd_t after fixing contexts/booleans
semanage permissive -d httpd_t
```

### Inspect All Local SELinux Customizations

Before migrating a host or writing Ansible playbooks, dump every non-default port, file context, and boolean customization cleanly:

`[ROOT]`
```bash
semanage export
# Or inspect modified booleans only:
semanage boolean -l -C
```

### Clone Existing Contexts for Non-Standard Paths

When relocating a service directory (for example, moving `/var/lib/pgsql` to `/srv/pgsql`), use `semanage fcontext -a -e` (equivalency) instead of hand-writing regexes; it mirrors every subdirectory rule automatically:

`[ROOT]`
```bash
semanage fcontext -a -e /var/lib/pgsql /srv/pgsql
restorecon -Rv /srv/pgsql
```

> **Watch out:** Avoid blindly piping `ausearch` output into `audit2allow -M mypol && semodule -i mypol.pp`. Nine times out of ten, a denial is caused by a mislabeled file (`restorecon`) or an existing SELinux boolean (`setsebool -P`), not a missing policy rule. Always inspect `sealert -a /var/log/audit/audit.log` first before generating custom `.pp` modules.

## firewalld Policies and Container Zones

### Use Policy Objects Instead of Legacy Direct Rules

In EL 9 (`firewalld` >= 0.9 with `nftables`), legacy `--direct` rules bypass native zone/nftables integration and are deprecated. Use **policy objects** to control cross-zone forwarded traffic (such as container bridge egress or VPN-to-LAN forwarding):

`[ROOT]`
```bash
# Inspect built-in and custom policies
firewall-cmd --get-policies
firewall-cmd --info-policy=allow-host-ipv6

# Example: permit forwarding from WireGuard zone (wg) to internal zone
firewall-cmd --permanent --new-policy wg-to-internal
firewall-cmd --permanent --policy wg-to-internal --add-ingress-zone wg
firewall-cmd --permanent --policy wg-to-internal --add-egress-zone internal
firewall-cmd --permanent --policy wg-to-internal --set-target ACCEPT
firewall-cmd --reload
```

### Container Compatibility with firewalld

Podman (native on EL 9) uses `netavark` and integrates cleanly with `firewalld` without requiring the `docker` zone hacks. If you install Docker CE on Rocky/Alma/RHEL 9, verify `docker0` is assigned to the `docker` zone and masquerading is enabled on the outbound zone if containers cannot reach external DNS:

`[ROOT]`
```bash
firewall-cmd --get-zone-of-interface=docker0
firewall-cmd --zone=public --query-masquerade
# After reloading firewalld, always restart docker so Docker re-injects its nft/iptables chains:
systemctl restart docker
```

> **Watch out:** Running `firewall-cmd --reload` on a host running Docker flushes Docker's runtime NAT/filter chains unless `firewalld` is aware of the `docker` zone or Docker is restarted immediately afterward. Plan firewall reloads during maintenance windows on Docker hosts, or migrate workloads to rootless/rootful Podman + `netavark`.

## NetworkManager Multi-Homed and VLAN Tricks

### Create a Persistent Tagged VLAN Interface via nmcli

`[ROOT]`
```bash
nmcli connection add type vlan con-name vlan120 ifname ens18.120 \
  vlan.parent ens18 vlan.id 120 \
  ipv4.method manual ipv4.addresses 10.120.0.25/24 \
  802-3-ethernet.mtu 9000

nmcli connection up vlan120
```

### Prevent DHCP from Overwriting Manual DNS Servers

When an interface gets its IP via DHCP (for example, cloud VPCs) but you want to pin custom internal DNS resolvers:

`[ROOT]`
```bash
nmcli connection modify ens18 ipv4.ignore-auto-dns yes
nmcli connection modify ens18 ipv4.dns "10.10.0.10 10.10.0.11"
nmcli connection up ens18
```

## Custom tuned Profiles and Cockpit Extensions

### Inherit and Override a Base tuned Profile

Rather than fighting `tuned` over `/etc/sysctl.d/` precedence, create a custom child profile under `/etc/tuned/` that inherits `virtual-guest` or `throughput-performance`:

`[ROOT]`
```bash
mkdir -p /etc/tuned/prod-server

cat <<'EOF' > /etc/tuned/prod-server/tuned.conf
[main]
summary=Production server tuning inheriting virtual-guest
include=virtual-guest

[sysctl]
vm.swappiness=10
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.somaxconn=4096
EOF

tuned-adm profile prod-server
tuned-adm verify
```
