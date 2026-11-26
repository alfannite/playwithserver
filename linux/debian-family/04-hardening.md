# Debian, Ubuntu, and Proxmox VE Security Hardening

Production-safe security baseline covering `ufw` (with Docker egress/ingress safety), AppArmor enforcement, `unattended-upgrades`, APT signing hygiene, and Proxmox VE host controls.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Firewall Baseline with UFW and Docker Safety](#firewall-baseline-with-ufw-and-docker-safety)
- [AppArmor Enforcement Without Breaking Apps](#apparmor-enforcement-without-breaking-apps)
- [Automated Security Patching](#automated-security-patching)
- [Proxmox VE Host Security](#proxmox-ve-host-security)
- [APT Repository Signature Verification](#apt-repository-signature-verification)

## Firewall Baseline with UFW and Docker Safety

Configure `ufw` on standard Debian and Ubuntu servers (not Proxmox VE hosts). Always allow SSH before enabling the firewall.

`[ROOT]`
```bash
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# Allow SSH with rate-limiting (blocks >6 connections in 30s per IP)
ufw limit 22/tcp comment 'Rate-limited SSH'

# Example public reverse-proxy ports
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

ufw --force enable
ufw status verbose
```

### Preventing the Docker UFW Bypass

Docker publishes container ports via `DNAT` in the `PREROUTING` chain and routes them through the `FORWARD` chain, bypassing `ufw`'s `INPUT` rules completely. Two production-safe mitigations prevent accidental public exposure:

1. **Bind internal container ports to loopback or private bridge IPs:**
   ```bash
   # Safe: unreachable from external NICs
   docker run -d -p 127.0.0.1:5432:5432 postgres:16
   ```
2. **Restrict forwarded ingress in `/etc/ufw/after.rules` via `DOCKER-USER`:**
   Allow established return traffic and private management/container subnets, then drop unsolicited external ingress hitting non-public container ports. Keep `ufw default allow routed` off unless acting as a router, and allow explicit public ports (80/443) in `DOCKER-USER` before a final drop on the external NIC (`eth0`):

`[ROOT]`
```text
# Append to /etc/ufw/after.rules (replace eth0 with your WAN NIC)
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i eth0 -p tcp -m multiport --dports 80,443 -j RETURN
-A DOCKER-USER -i eth0 -s 10.10.0.0/16 -j RETURN
-A DOCKER-USER -i eth0 -j DROP
-A DOCKER-USER -j RETURN
COMMIT
```

Reload `ufw` and verify `DOCKER-USER` rules take effect without breaking container outbound internet access:

`[ROOT]`
```bash
ufw reload
iptables -L DOCKER-USER -n -v
```

> **Watch out:** Never set `"iptables": false` in `/etc/docker/daemon.json` as a shortcut to make `ufw` work; disabling Docker iptables breaks container DNS, outbound NAT, and inter-container bridge isolation unless you hand-craft every NAT and forwarding rule yourself.

## AppArmor Enforcement Without Breaking Apps

Verify AppArmor is active in the kernel and inspect confined vs. complaining profiles:

`[ROOT]`
```bash
aa-status
```

When a custom configuration (for example, moving MySQL or Nginx data paths to `/srv/data`) triggers an AppArmor `DENIED` event, add the custom directory under `/etc/apparmor.d/local/` rather than editing the upstream profile or disabling AppArmor:

`[ROOT]`
```bash
# Example: permit mysqld access to custom data directory /srv/mysql
cat <<'EOF' >> /etc/apparmor.d/local/usr.sbin.mysqld
/srv/mysql/ r,
/srv/mysql/** rwk,
EOF

apparmor_parser -r /etc/apparmor.d/usr.sbin.mysqld
systemctl restart mysql
```

Check for AppArmor denials in the kernel log:

`[ROOT]`
```bash
dmesg -T | grep -i apparmor
journalctl -k --grep='apparmor="DENIED"' --no-pager
```

## Automated Security Patching

Keep security updates automated via `unattended-upgrades` while restricting scope to security pockets so feature upgrades do not introduce breaking changes mid-week.

Verify active origins in `/etc/apt/apt.conf.d/50unattended-upgrades` and add local overrides in `51-local-unattended`:

`[ROOT]`
```bash
cat <<'EOF' > /etc/apt/apt.conf.d/51-local-unattended
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF

systemctl status apt-daily.timer apt-daily-upgrade.timer --no-pager
```

## Proxmox VE Host Security

Do not install `ufw` or `firewalld` on Proxmox VE hypervisors; they conflict with `pve-firewall` and bridge netfilter rules used by VMs and LXC containers.

1. **Enable the Proxmox Cluster Firewall safely:**
   Before enabling the datacenter firewall in the GUI or `/etc/pve/firewall/cluster.fw`, explicitly allow TCP `22` (SSH) and TCP `8006` (Web UI) from your management subnet, plus Corosync UDP `5405-5412` between cluster nodes.
2. **Restrict Web UI (`pveproxy`) binding to the management interface:**
   `[ROOT]`
   ```bash
   cat <<'EOF' > /etc/default/pveproxy
   LISTEN_IP="10.10.10.5"
   ALLOW_FROM="10.10.0.0/16,127.0.0.1"
   DENY_FROM="all"
   POLICY="allow"
   EOF
   systemctl restart pveproxy
   ```
3. **Require TOTP/WebAuthn 2FA** for `root@pam` and create separate least-privilege `@pve` accounts for daily VM administration and backup jobs.

> **Watch out:** Enabling the Proxmox datacenter firewall without an explicit management-subnet allow rule for ports `8006` and `22` locks you out of the web UI immediately. If locked out via console, run `pve-firewall stop` to restore access temporarily.

## APT Repository Signature Verification

Avoid legacy `apt-key add` (deprecated and removed in modern Debian/Ubuntu), which trusts a third-party GPG key globally for **all** repositories. Always scope external repository keys to `/etc/apt/keyrings/` and bind them explicitly with `Signed-By:` inside `.sources` or `.list` files:

`[ROOT]`
```bash
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat <<EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
```
