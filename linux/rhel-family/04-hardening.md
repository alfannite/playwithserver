# Rocky, AlmaLinux, RHEL 9, and Fedora Security Hardening

Production-safe Enterprise Linux security baseline preserving SELinux Enforcing mode, `firewalld` zone segmentation, system crypto policies, locked-down Cockpit/SSH access, and `auditd` telemetry without breaking containers or Kubernetes.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Keeping SELinux Enforcing Safely](#keeping-selinux-enforcing-safely)
- [firewalld Zone and Rich-Rule Hardening](#firewalld-zone-and-rich-rule-hardening)
- [System-Wide Crypto Policies](#system-wide-crypto-policies)
- [SSH and Cockpit Access Controls](#ssh-and-cockpit-access-controls)
- [Auditd and Automated Security Patching](#auditd-and-automated-security-patching)

## Keeping SELinux Enforcing Safely

Leave SELinux in `Enforcing` mode (`SELINUX=enforcing` in `/etc/selinux/config`). Modern Podman, Docker, and Kubernetes distributions ship SELinux container policies (`container-selinux`) that isolate container breakouts at the kernel level.

Verify SELinux enforcement and container policy availability:

`[ROOT]`
```bash
sestatus
rpm -q container-selinux
```

### Container Volume Labeling Without Disabling SELinux

When bind-mounting host directories into Podman or Docker containers on SELinux-enforcing hosts, append `:Z` (private exclusive label for one container) or `:z` (shared label across multiple containers) so the container can read/write its volume cleanly:

`[NON-ROOT]`
```bash
# Exclusive volume mount for a single container
podman run -d -v /srv/app-data:/data:Z myapp:latest

# Shared volume mount read by multiple containers
podman run -d -v /srv/shared-assets:/assets:z nginx:stable
```

> **Watch out:** Never pass `:Z` or `:z` on system directories like `/`, `/etc`, `/var`, or `/home`; relabeling `/etc` to `container_file_t` breaks host services (`sshd`, `systemd`, `chronyd`) immediately. Only use `:Z`/`:z` on dedicated application data directories under `/srv/` or `/opt/`.

## firewalld Zone and Rich-Rule Hardening

Strip unnecessary default services (such as `cockpit` and `dhcpv6-client` on static IPv4 servers) from the `public` zone and bind administrative ports strictly to management CIDRs.

`[ROOT]`
```bash
# Audit current public zone exposure
firewall-cmd --zone=public --list-all

# Remove unneeded default services from public zone
firewall-cmd --permanent --zone=public --remove-service=cockpit
firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client

# Restrict SSH to a bastion/management subnet (verify your current client IP first!)
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="10.10.0.0/16" service name="ssh" accept'
# Only remove global ssh AFTER confirming the rich rule covers your IP:
# firewall-cmd --permanent --zone=public --remove-service=ssh

# Enable logging for unicast dropped packets for intrusion visibility
firewall-cmd --set-log-denied=unicast

firewall-cmd --reload
firewall-cmd --zone=public --list-all
```

| Zone | Target | Use Case |
| :--- | :--- | :--- |
| `public` | `default` (reject) | Untrusted WAN/LAN NICs; explicit allow-list only |
| `drop` | `DROP` | Internet-facing hosts requiring silent packet drops |
| `internal` | `default` | Trusted private management or backend VLAN NICs |
| `trusted` | `ACCEPT` | Dedicated loopback/CNI/WireGuard interfaces where policy controls egress |

> **Watch out:** Never remove the global `ssh` service from the `public` zone until after you have verified your active SSH client IP matches the new `source address=` rich rule (`echo $SSH_CONNECTION`). Keep a second SSH session open while reloading `firewalld`.

## System-Wide Crypto Policies

EL 9 and Fedora unify OpenSSL, GnuTLS, OpenSSH, NSS, and Java cryptographic algorithms through `update-crypto-policies`, eliminating manual cipher lists across every daemon.

`[ROOT]`
```bash
# Inspect current policy (EL 9 defaults to DEFAULT: TLS 1.2+, SHA-256+, RSA >= 2048)
update-crypto-policies --show

# Optional stricter policy (TLS 1.2+/1.3, RSA >= 3072, blocks SHA-1 completely)
# Test client compatibility before enabling FUTURE in production:
# update-crypto-policies --set FUTURE
```

`DEFAULT` on RHEL/Rocky/Alma 9 already disables TLS 1.0/1.1, SSLv3, RC4, 3DES, and SHA-1 signatures. Only apply `FUTURE` after confirming all legacy monitoring agents, load balancers, and database clients support >=3072-bit RSA or ECDSA/Ed25519 keys.

## SSH and Cockpit Access Controls

### OpenSSH Drop-In on EL 9

EL 9 ships `/etc/ssh/sshd_config.d/50-redhat.conf` (and cloud images may ship `01-permitrootlogin.conf`). Place hardening overrides in `00-` or inspect lexical precedence via `sshd -T`:

`[ROOT]`
```bash
cat <<'EOF' > /etc/ssh/sshd_config.d/05-hardening.conf
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

sshd -t
sshd -T | grep -E 'permitrootlogin|passwordauthentication|pubkeyauthentication'
systemctl reload sshd
```

### Allow Custom SSH Port Through SELinux and firewalld

If changing SSH from port `22` to a custom port (for example, `2222`), register the port with SELinux **before** restarting `sshd`:

`[ROOT]`
```bash
semanage port -a -t ssh_port_t -p tcp 2222
firewall-cmd --permanent --add-port=2222/tcp
firewall-cmd --reload
```

### Restrict Cockpit Root Login

Disallowing direct `root` login in Cockpit forces operators to authenticate as an unprivileged `wheel` user and elevate explicitly:

`[ROOT]`
```bash
grep -qxF 'root' /etc/cockpit/disallowed-users || echo 'root' >> /etc/cockpit/disallowed-users
```

## Auditd and Automated Security Patching

Ensure the Linux audit subsystem (`auditd`) is running so SELinux AVC denials, privilege escalations, and `sudo` events are recorded under `/var/log/audit/audit.log`:

`[ROOT]`
```bash
systemctl enable --now auditd
auditctl -s
```

Verify `dnf-automatic` is active and monitor pending security advisories:

`[NON-ROOT]`
```bash
systemctl is-enabled dnf-automatic.timer
dnf updateinfo summary security
```
