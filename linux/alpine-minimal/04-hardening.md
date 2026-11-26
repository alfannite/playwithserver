# Alpine Linux Security Hardening

Practical production-safe hardening baselines for Alpine Linux VMs, edge routers, and minimal containers covering `doas`, OpenSSH, `nftables`/`awall`, `sysctl`, and package integrity without breaking Docker or Kubernetes workloads.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Least-Privilege `doas` Configuration](#least-privilege-doas-configuration)
- [OpenSSH Hardening](#openssh-hardening)
- [Firewalling with `nftables` or `awall`](#firewalling-with-nftables-or-awall)
- [Kernel `sysctl` Hardening](#kernel-sysctl-hardening)
- [Container Image Hardening Baseline](#container-image-hardening-baseline)
- [Package Integrity and Account Hygiene](#package-integrity-and-account-hygiene)

## Least-Privilege `doas` Configuration

Keep `/etc/doas.d/` minimal, explicit, and validated. Prefer per-role files over broad `nopass` grants.

```sh
# [ROOT] Enforce explicit authentication for wheel and scoped nopass only for non-destructive status checks
cat <<'EOF' > /etc/doas.d/20-wheel.conf
permit persist :wheel
permit nopass :wheel cmd /sbin/rc-status
EOF

chmod 0640 /etc/doas.d/20-wheel.conf
chown root:root /etc/doas.d/20-wheel.conf

# Verify syntax strictly
doas -C /etc/doas.d/20-wheel.conf
```

## OpenSSH Hardening

```sh
# [ROOT] Confirm drop-in include exists in /etc/ssh/sshd_config
grep -E '^Include /etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config

# [ROOT] Write hardened drop-in config
mkdir -p /etc/ssh/sshd_config.d
cat <<'EOF' > /etc/ssh/sshd_config.d/99-hardening.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding local
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowGroups wheel
EOF

# Validate syntax and reload without dropping existing session
sshd -t
rc-service sshd reload
```

> **Watch out:** Verify public-key SSH login as your non-root `wheel` user in a second terminal before disconnecting. On diskless hosts, run `lbu commit -d` after confirming SSH works so your keys and `sshd_config.d` persist across reboots.

## Firewalling with `nftables` or `awall`

Choose **either** native `nftables` or `awall` (which compiles JSON policies to `iptables`/`nftables`). Never run both managers on the same host.

### Option A: Native `nftables` (Container-Safe Table) `[ROOT]`

Managing an isolated table (`inet host_filter`) instead of calling `flush ruleset` prevents wiping Docker or containerd NAT/forwarding chains on firewall reload.

```sh
# [ROOT] Install nftables
apk add nftables

cat <<'EOF' > /etc/nftables.nft
#!/usr/sbin/nft -f

table inet host_filter
delete table inet host_filter

table inet host_filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state invalid drop
        ct state established,related accept

        # Allow essential ICMP / ICMPv6 (PMTUD & IPv6 NDP)
        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept
        ip6 nexthdr icmpv6 icmpv6 type { echo-request, destination-unreachable, packet-too-big, time-exceeded, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

        # SSH and web services
        tcp dport { 22, 80, 443 } accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

# Validate syntax, enable at boot, and load
nft -c -f /etc/nftables.nft
rc-update add nftables boot
rc-service nftables start
nft list table inet host_filter
```

### Option B: `awall` (Alpine Wall) for Edge Hosts and Routers `[ROOT]`

```sh
# [ROOT] Install awall
apk add awall ip6tables iptables

# Define a minimal host policy in /etc/awall/optional/base.json
mkdir -p /etc/awall/optional
cat <<'EOF' > /etc/awall/optional/base.json
{
  "description": "Base host policy",
  "zone": {
    "WAN": { "iface": "eth0" }
  },
  "policy": [
    { "in": "_fw", "out": "WAN", "action": "accept" },
    { "in": "WAN", "out": "_fw", "action": "drop" }
  ],
  "filter": [
    { "in": "WAN", "out": "_fw", "service": [ "ssh", "http", "https" ], "action": "accept" },
    { "in": "WAN", "out": "_fw", "service": "ping", "action": "accept", "flow-limit": { "count": 10, "interval": 1 } }
  ]
}
EOF

# Enable and activate (prompts for confirmation; auto-reverts in 10s if SSH disconnects)
awall enable base
awall activate
```

> **Watch out:** On Docker hosts running Alpine `sys` mode, `awall` overwrites `iptables` rules during `awall activate` and will strip Docker's `DOCKER-USER` / `DOCKER` chains unless Docker is restarted afterward or you use the isolated `nftables` named-table pattern above.

## Kernel `sysctl` Hardening

Apply kernel hardening via `/etc/sysctl.d/` and ensure the OpenRC `sysctl` service runs at `boot` runlevel.

```sh
# [ROOT] Production-safe sysctl baseline (leaves ip_forward untouched for routers/Docker)
cat <<'EOF' > /etc/sysctl.d/99-security.conf
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF

rc-update add sysctl boot
sysctl -p /etc/sysctl.d/99-security.conf
```

## Container Image Hardening Baseline

When using Alpine as an OCI container base image:

1. Always run the workload as a dedicated non-root system user (`addgroup -S` / `adduser -S`).
2. Strip build tools using `--virtual .build-deps` or multi-stage builds.
3. Run containers with `--read-only`, `--cap-drop=ALL`, and a writable `tmpfs` only for `/tmp`.

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata \
 && addgroup -S appgroup \
 && adduser -S -G appgroup -H -s /sbin/nologin appuser
COPY --chown=appuser:appgroup ./server /usr/local/bin/server
USER appuser
ENTRYPOINT ["/usr/local/bin/server"]
```

## Package Integrity and Account Hygiene

```sh
# [ROOT] Audit all files owned by installed packages for unexpected modifications
apk audit --full

# [ROOT] Lock direct password login for root after confirming wheel + doas access
passwd -l root

# [ROOT] Inventory all SUID/SGID binaries on the host
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null

# [ROOT] Enable unattended security update checks via periodic cron (inspect output; do not auto-reboot blindly)
cat <<'EOF' > /etc/periodic/daily/apk-audit-updates
#!/bin/sh
apk update >/dev/null 2>&1
apk list --upgradable | logger -t apk-updates
EOF
chmod 0755 /etc/periodic/daily/apk-audit-updates
```
