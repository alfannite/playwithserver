# Linux Common Security Hardening

Production-safe cross-distro hardening baseline covering OpenSSH, kernel `sysctl` protections, `systemd` service sandboxing, mount flags, and privilege auditing without breaking Docker, Kubernetes, or SSH access.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [SSH Daemon Baseline](#ssh-daemon-baseline)
- [Kernel Security Parameters](#kernel-security-parameters)
- [systemd Unit Sandboxing](#systemd-unit-sandboxing)
- [Filesystem Mount Hardening](#filesystem-mount-hardening)
- [Privilege Escalation and Audit Controls](#privilege-escalation-and-audit-controls)

## SSH Daemon Baseline

Place overrides in `/etc/ssh/sshd_config.d/10-hardening.conf` instead of modifying `/etc/ssh/sshd_config` directly. OpenSSH reads files in lexical order and **first match wins**, so prefixing with `10-` guarantees your directives override distro defaults (such as `50-cloud-init.conf`).

`[ROOT]`
```bash
mkdir -p /etc/ssh/sshd_config.d

cat <<'EOF' > /etc/ssh/sshd_config.d/10-hardening.conf
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30s
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
EOF
```

Validate configuration syntax and effective resolved values before reloading:

`[ROOT]`
```bash
sshd -t
sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries'
systemctl reload sshd 2>/dev/null || systemctl reload ssh
```

> **Watch out:** Always verify key-based login in a **second terminal session** before disconnecting your current session. Cloud images frequently ship `/etc/ssh/sshd_config.d/50-cloud-init.conf` or `60-cloudimg-settings.conf` containing `PasswordAuthentication yes`; verify `sshd -T` reports `passwordauthentication no` because first-match semantics mean a `99-` file can be silently ignored if a `50-` file sets the same directive first.

## Kernel Security Parameters

Apply defense-in-depth kernel controls that remain compatible with container runtimes (Docker, containerd, Podman) and Kubernetes CNI plugins.

`[ROOT]`
```bash
cat <<'EOF' > /etc/sysctl.d/99-security-baseline.conf
# Hide kernel pointers and restrict dmesg to CAP_SYSLOG
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1

# Restrict unprivileged eBPF and ptrace attachment to direct children
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 1

# Protect against symlink/hardlink/FIFO TOCTOU attacks in world-writable dirs
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# TCP/IP stack hardening (safe for routed & container hosts)
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Use loose reverse path filtering (2) instead of strict (1) for multi-homed/K8s/WireGuard hosts
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF

sysctl --system
```

| Parameter | Safe Value | Why Not Stricter? |
| :--- | :--- | :--- |
| `net.ipv4.conf.all.rp_filter` | `2` (loose) | Strict (`1`) drops asymmetric traffic on WireGuard, BGP, Keepalived VIPs, and multi-NIC nodes |
| `net.ipv4.ip_forward` | Leave unset (`1` if Docker/K8s/WireGuard) | Forcing `0` immediately breaks container networking and VPN routing |
| `kernel.yama.ptrace_scope` | `1` | Allows parent debuggers/tracers while blocking cross-process credential scraping |
| `fs.suid_dumpable` | `0` | Prevents setuid binaries from dumping sensitive memory to core files |

> **Watch out:** Never set `net.ipv4.ip_forward = 0` or `net.bridge.bridge-nf-call-iptables = 0` on hosts running Docker, Podman rootful bridges, Proxmox routed VMs, or Kubernetes. Container runtimes depend on IP forwarding and bridge netfilter hooks to route pod and container egress traffic.

## systemd Unit Sandboxing

Audit the security exposure score of running services before writing drop-in restrictions:

`[NON-ROOT]`
```bash
systemd-analyze security
systemd-analyze security nginx.service
```

Apply practical sandboxing to custom application units (adjust `ReadWritePaths=` to match actual data/log directories):

```ini
[Service]
DynamicUser=yes
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
LockPersonality=yes
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
ReadWritePaths=/var/lib/myapp /var/log/myapp
```

Test a newly sandboxed service immediately and inspect denials in `journalctl -u myapp -n 50`.

## Filesystem Mount Hardening

Restrict execution and device node creation on volatile or user-writable mounts when dedicated partitions exist:

| Mountpoint | Recommended Flags | Caution |
| :--- | :--- | :--- |
| `/dev/shm` | `defaults,nodev,nosuid,noexec` | Verify apps (e.g., certain JIT engines or Oracle DB) do not execute from `/dev/shm` |
| `/tmp` | `defaults,nodev,nosuid` | Adding `noexec` on `/tmp` breaks `apt`/`dpkg` hooks, Python wheel builds, and Ansible unless overridden |
| `/var/tmp` | `defaults,nodev,nosuid,noexec` | Safe on most server workloads |
| `/home` | `defaults,nodev,nosuid` | Do not add `noexec` if operators run local scripts or CI runners in `/home` |

Example `/etc/fstab` line for `/dev/shm`:

`[ROOT]`
```bash
tmpfs  /dev/shm  tmpfs  defaults,nodev,nosuid,noexec,size=2G  0  0
```

Apply without rebooting:

`[ROOT]`
```bash
mount -o remount /dev/shm
findmnt /dev/shm
```

## Privilege Escalation and Audit Controls

### Harden sudoers with Drop-Ins

Never edit `/etc/sudoers` directly; use `visudo -f` on `/etc/sudoers.d/` files so syntax errors cannot lock out privilege escalation.

`[ROOT]`
```bash
visudo -f /etc/sudoers.d/10-ops-policy
```

Recommended contents:

```text
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
Defaults passwd_tries=3
Defaults timestamp_timeout=5
```

### Lock Unused Accounts and Audit SUID Binaries

`[ROOT]`
```bash
# List accounts with valid login shells
awk -F: '$7 !~ /(nologin|false|sync|shutdown|halt)$/ {print $1, $3, $7}' /etc/passwd

# Check for accounts with empty password hashes (must return empty)
awk -F: '($2 == "" ) {print $1}' /etc/shadow

# Inventory SUID/SGID binaries on the root filesystem
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | sort
```
