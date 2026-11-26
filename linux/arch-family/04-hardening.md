# Arch Family Security Hardening

Production-safe hardening baselines for Arch Linux, EndeavourOS, and CachyOS covering SSH, `nftables`/`ufw`, kernel sysctls, optional AppArmor, and AUR supply-chain hygiene without breaking Docker, Podman, or Kubernetes.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [SSH Daemon Hardening](#ssh-daemon-hardening)
- [Firewall Configuration (`nftables` vs `ufw`)](#firewall-configuration-nftables-vs-ufw)
- [Kernel and Sysctl Hardening](#kernel-and-sysctl-hardening)
- [Optional AppArmor Mandatory Access Control](#optional-apparmor-mandatory-access-control)
- [Brute-Force Protection and Audit Logging](#brute-force-protection-and-audit-logging)
- [AUR Supply-Chain and Sudo Hygiene](#aur-supply-chain-and-sudo-hygiene)

## SSH Daemon Hardening

Always keep an active SSH session open while applying SSH changes and test syntax before reloading.

```bash
# [ROOT] Ensure sshd_config includes drop-in directory (default on modern Arch)
grep -E '^Include /etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config

# [ROOT] Deploy hardened drop-in config
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding local
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowGroups wheel
EOF

# Validate syntax and effective settings before reloading
sudo sshd -t
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|allowgroups'
sudo systemctl reload sshd
```

> **Watch out:** Verify your SSH public key is installed in `~/.ssh/authorized_keys` (`chmod 600`) and test a **second** SSH login in a new terminal before closing your current session. Locking out `root` and passwords simultaneously without a working key locks you out of headless servers.

## Firewall Configuration (`nftables` vs `ufw`)

Arch ships `iptables-nft` by default. Choose **one** firewall frontend (`nftables` native or `ufw`)—never run `nftables.service`, `ufw.service`, and `firewalld.service` simultaneously.

### Option A: Native `nftables` (Container-Safe) `[ROOT]`

Using a dedicated `inet filter` table with an `input` chain (and leaving `forward` policy open or scoped when Docker/K8s manages its own chains) avoids flushing Docker's NAT/forwarding rules.

```bash
# [ROOT] Install nftables
sudo pacman -S --needed nftables

sudo tee /etc/nftables.conf >/dev/null <<'EOF'
#!/usr/bin/nft -f
# Only manage our own table so Docker/Kubernetes ip/ip6 nat & filter tables stay intact
table inet host_filter
delete table inet host_filter

table inet host_filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state invalid drop
        ct state established,related accept

        # ICMP / ICMPv6 essential for Path MTU Discovery and IPv6 NDP
        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept
        ip6 nexthdr icmpv6 icmpv6 type { echo-request, destination-unreachable, packet-too-big, time-exceeded, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

        # Management and application ports
        tcp dport { 22, 80, 443 } accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

# Validate syntax, enable, and inspect active ruleset
sudo nft -c -f /etc/nftables.conf
sudo systemctl enable --now nftables
sudo nft list table inet host_filter
```

### Option B: `ufw` for Fast Host Policies `[ROOT]`

```bash
# [ROOT] Install and configure ufw
sudo pacman -S --needed ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 22/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo systemctl enable --now ufw
sudo ufw status verbose
```

> **Watch out:** Never put `flush ruleset` at the top of `/etc/nftables.conf` on a Docker, Podman, or Kubernetes node. `flush ruleset` wipes all container NAT/forwarding tables on reload and immediately breaks pod/container networking. Delete and recreate only your own named table (`table inet host_filter`) as shown above.

## Kernel and Sysctl Hardening

### Safe Production `sysctl` Baseline `[ROOT]`

These settings harden TCP/IP, restrict kernel pointer/dmesg leaks, and preserve container compatibility (leaves `net.ipv4.ip_forward` untouched for Docker/K8s and `kernel.unprivileged_userns_clone=1` for rootless Podman/Flatpak).

```bash
# [ROOT] Apply production-safe kernel hardening parameters
sudo tee /etc/sysctl.d/99-security.conf >/dev/null <<'EOF'
# Restrict kernel pointers and dmesg to root
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.sysrq = 0

# Protect hardlinks, symlinks, and FIFOs in world-writable dirs
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# Network stack hardening
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF

sudo sysctl --system
```

| Parameter | Value | Note |
| :--- | :--- | :--- |
| `net.ipv4.conf.all.rp_filter` | `2` (loose) | Loose mode avoids dropping asymmetric traffic on WireGuard/BGP/multi-NIC K8s nodes |
| `kernel.yama.ptrace_scope` | `1` | Blocks arbitrary process memory inspection while keeping `strace`/`gdb` on child processes working |
| `linux-hardened` kernel | Optional | Disables unprivileged user namespaces by default (`kernel.unprivileged_userns_clone=0`), breaking rootless Podman/Chromium/Flatpak unless re-enabled |

## Optional AppArmor Mandatory Access Control

Arch kernels include AppArmor support compiled in, disabled by default at boot.

```bash
# [ROOT] Install AppArmor utilities and audit integration
sudo pacman -S --needed apparmor audit

# Enable AppArmor and auditd services
sudo systemctl enable --now apparmor auditd
```

Add the LSM kernel parameters to your bootloader (`/etc/default/grub` -> `GRUB_CMDLINE_LINUX_DEFAULT`, or `/boot/loader/entries/*.conf` -> `options`):

```text
lsm=landlock,lockdown,yama,integrity,apparmor,bpf
```

```bash
# [ROOT] [REBOOT] Regenerate GRUB config (if using GRUB) and reboot
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot

# [ROOT] After reboot, verify AppArmor is active and inspect profiles
aa-enabled
sudo aa-status
```

## Brute-Force Protection and Audit Logging

### `sshguard` with `nftables` and `journald` `[ROOT]`

`sshguard` is lighter than Python-based `fail2ban` and reads directly from `systemd-journald`.

```bash
# [ROOT] Install sshguard
sudo pacman -S --needed sshguard

sudo tee /etc/sshguard.conf >/dev/null <<'EOF'
BACKEND="/usr/lib/sshguard/sshg-fw-nft-sets"
LOGREADER="LANG=C /usr/bin/journalctl -afb -p info -n1 -t sshd -o cat"
THRESHOLD=30
BLOCK_TIME=300
DETECTION_TIME=1800
WHITELIST_FILE=/etc/sshguard.whitelist
EOF

# Whitelist private management subnets
sudo tee /etc/sshguard.whitelist >/dev/null <<'EOF'
127.0.0.1
::1
10.0.0.0/8
EOF

sudo systemctl enable --now sshguard
```

### Enable `auditd` Baseline Rules `[ROOT]`

```bash
# [ROOT] Watch identity files and sudoers for unauthorized modification
sudo tee /etc/audit/rules.d/50-identity.rules >/dev/null <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/ssh/sshd_config.d/ -p wa -k sshd
EOF

sudo augenrules --load
sudo auditctl -l
```

## AUR Supply-Chain and Sudo Hygiene

### Enforce AUR Review and Clean Chroot Builds `[NON-ROOT]`

- Keep `Review` enabled in `/etc/paru.conf` (default) and inspect `source=()`, `sha256sums=()`, and `.install` scripts on every AUR install or upgrade.
- Prefer official `extra` packages over AUR packages whenever available.
- For production hosts, build AUR packages on a dedicated build VM in a clean chroot (`devtools`) and serve a signed local repo rather than installing compilers on production servers:

```bash
# [ROOT] On a dedicated build machine: install devtools
sudo pacman -S --needed devtools

# [NON-ROOT] Build a PKGBUILD inside an isolated clean Arch chroot
cd /path/to/pkgbuild-dir
extra-x86_64-build
```

### Configure PAM `faillock` Policy `[ROOT]`

Arch enables `pam_faillock` by default (3 failed logins lock an account for 10 minutes). Tune or inspect lockouts:

```bash
# [ROOT] View lockout counters for a user
sudo faillock --user ops

# [ROOT] Clear an accidental lockout
sudo faillock --user ops --reset
```
