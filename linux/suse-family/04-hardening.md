# openSUSE Family Security Hardening

Production-safe security baselines for openSUSE Leap, Tumbleweed, and MicroOS covering SSH, `firewalld`, SELinux vs AppArmor, `sysctl`, `auditd`, and automated patching without breaking Podman, Docker, or Kubernetes.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [OpenSSH Hardening (`/etc/ssh/sshd_config.d/`)](#openssh-hardening-etcsshsshd_configd)
- [Container-Safe `firewalld` Hardening](#container-safe-firewalld-hardening)
- [MAC Enforcement: SELinux (Tumbleweed/MicroOS) vs AppArmor (Leap)](#mac-enforcement-selinux-tumbleweedmicroos-vs-apparmor-leap)
- [Kernel `sysctl` Hardening](#kernel-sysctl-hardening)
- [Audit Logging and Brute-Force Protection](#audit-logging-and-brute-force-protection)
- [Automated Security Updates and Immutable Hygiene](#automated-security-updates-and-immutable-hygiene)

## OpenSSH Hardening (`/etc/ssh/sshd_config.d/`)

Because Tumbleweed and MicroOS store the vendor config at `/usr/etc/ssh/sshd_config`, always deploy hardening via `/etc/ssh/sshd_config.d/`.

```bash
# [ROOT] Deploy key-only hardened SSH drop-in
sudo mkdir -p /etc/ssh/sshd_config.d
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

# Validate syntax and effective running parameters before reloading
sudo sshd -t
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|allowgroups'
sudo systemctl reload sshd
```

> **Watch out:** Keep an existing SSH session open and verify key-based login as a `wheel` user in a second terminal before disconnecting. On MicroOS, `/etc` is writable directly via overlayfs—SSH config edits take effect immediately without requiring `transactional-update`.

## Container-Safe `firewalld` Hardening

openSUSE uses `firewalld` on top of `nftables`. Keep the default zone strict (`public` or `drop`) while preserving `docker` / `trusted` interfaces for container bridges and CNI plugins.

```bash
# [ROOT] Ensure firewalld is enabled and inspect current zone bindings
sudo systemctl enable --now firewalld
sudo firewall-cmd --get-active-zones

# Remove unnecessary default services (e.g., dhcpv6-client/mdns/cockpit if unused)
sudo firewall-cmd --permanent --zone=public --remove-service=mdns 2>/dev/null || true

# Allow only required inbound services
sudo firewall-cmd --permanent --zone=public --add-service=ssh
sudo firewall-cmd --permanent --zone=public --add-service=https

# Restrict SSH to a management subnet via rich rules (optional; remove broad ssh service after testing)
# sudo firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="10.10.0.0/24" service name="ssh" accept'

sudo firewall-cmd --reload
sudo firewall-cmd --zone=public --list-all
```

### Container Networking Compatibility (Podman / Docker / K3s) `[ROOT]`

- Podman (`netavark`) and Docker manage their own `nftables` / `firewalld` zones automatically.
- On K3s / RKE2 nodes running `firewalld`, add the pod/service CIDRs and CNI interface (`cni0`, `flannel.1`, `cilium_*`) to the `trusted` zone so inter-pod routing is not dropped:

```bash
# [ROOT] Example for K3s/RKE2 node running firewalld
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --reload
```

> **Watch out:** Running `firewall-cmd --reload` on a Docker host can flush Docker's dynamic rules if Docker did not register its `docker` zone cleanly; verify container egress and port publishing after any firewall reload, and restart `docker.service` if published ports stop responding.

## MAC Enforcement: SELinux (Tumbleweed/MicroOS) vs AppArmor (Leap)

### SELinux on Tumbleweed and MicroOS `[ROOT]`

Keep SELinux in `Enforcing` mode and fix context/port policies instead of disabling it.

```bash
# [NON-ROOT] Verify Enforcing mode
sestatus

# [ROOT] Allow nginx/httpd to bind to a custom port (e.g., 8443)
sudo semanage port -a -t http_port_t -p tcp 8443

# [ROOT] Allow reverse-proxy outbound connections from nginx/httpd
sudo setsebool -P httpd_can_network_connect on

# [ROOT] Restore canonical file labels after moving/extracting files into /srv or /etc
sudo restorecon -Rv /srv/www
```

For Podman/Docker bind mounts on SELinux hosts, append `:Z` (private exclusive label) or `:z` (shared container label) to volume mounts (`-v /srv/app:/app:Z`), never `:Z` on system directories like `/etc` or `/usr`.

### AppArmor on openSUSE Leap `[ROOT]`

```bash
# [ROOT] Verify AppArmor profiles and enforcement state
sudo aa-status

# Switch a profile from complain to enforce mode
sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx

# Interactively update a profile from logged denials
sudo aa-logprof
```

## Kernel `sysctl` Hardening

```bash
# [ROOT] Deploy production-safe kernel hardening without breaking container networking
sudo tee /etc/sysctl.d/99-security.conf >/dev/null <<'EOF'
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.sysrq = 0

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

sudo sysctl --system
```

## Audit Logging and Brute-Force Protection

### `auditd` Identity and Sudoers Watch Rules `[ROOT]`

```bash
# [ROOT] Install audit if not already present (Leap/Tumbleweed)
sudo zypper in --no-recommends audit

sudo tee /etc/audit/rules.d/50-identity.rules >/dev/null <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config.d/ -p wa -k sshd
EOF

sudo systemctl enable --now auditd
sudo augenrules --load
```

### `sshguard` Integrated with `firewalld` `[ROOT]`

```bash
# [ROOT] Install sshguard (Leap / Tumbleweed)
sudo zypper in --no-recommends sshguard
sudo systemctl enable --now sshguard
```

## Automated Security Updates and Immutable Hygiene

### Leap: Automated Security Patching via `yast2-online-update-configuration` or Timer `[ROOT]`

```bash
# [ROOT] Dry-run unattended security patches on Leap
sudo zypper --non-interactive patch --category security --dry-run
```

### MicroOS: Automatic Verified Snapshots + Controlled Reboots `[ROOT]`

MicroOS runs `transactional-update.timer` daily to stage verified updates in a new read-only Btrfs snapshot while `health-checker` validates boot health and automatically rolls back to the last known-good snapshot if core services fail after reboot.

```bash
# [ROOT] Verify automatic update timer, reboot manager, and boot health-checker
systemctl is-enabled transactional-update.timer rebootmgr.service health-checker.service
```
