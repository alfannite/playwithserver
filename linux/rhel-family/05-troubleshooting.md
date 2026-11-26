# Rocky, AlmaLinux, RHEL 9, and Fedora Troubleshooting

Symptom-to-fix matrix and diagnostic workflows for SELinux denials, `dnf`/`rpm` issues, `firewalld` packet drops, NetworkManager profile failures, and `tuned` parameter conflicts.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Symptom to Fix Matrix](#symptom-to-fix-matrix)
- [SELinux Denial Diagnosis and Resolution](#selinux-denial-diagnosis-and-resolution)
- [DNF and RPM Database Recovery](#dnf-and-rpm-database-recovery)
- [firewalld and NetworkManager Debugging](#firewalld-and-networkmanager-debugging)
- [Performance and tuned Drift Triage](#performance-and-tuned-drift-triage)
- [High-Signal One-Liners](#high-signal-one-liners)

## Symptom to Fix Matrix

| Symptom | First Diagnostic Command | Common Root Cause | Targeted Fix |
| :--- | :--- | :--- | :--- |
| Service fails to bind custom port (`Permission denied`) | `ausearch -m AVC -ts recent` | SELinux port type missing (`http_port_t`, `ssh_port_t`) | `semanage port -a -t <type> -p tcp <port>` |
| Web/app gets `403` or `EACCES` on moved files | `ls -Z /srv/www` | File moved (`mv`) retaining `user_home_t`/`tmp_t` context | `semanage fcontext` + `restorecon -Rv /srv/www` |
| Reverse proxy returns `502` (`Permission denied` to upstream) | `getsebool httpd_can_network_connect` | SELinux boolean blocks outbound connections from `httpd_t` | `setsebool -P httpd_can_network_connect on` |
| Container loses outbound network after `firewall-cmd --reload` | `nft list ruleset \| grep -i docker` | Firewalld reload flushed Docker's runtime chains | `systemctl restart docker` or assign `docker0` to `docker` zone |
| EPEL package install fails with missing dependency | `dnf repolist enabled` | CRB repository not enabled on Rocky/Alma/RHEL 9 | `dnf config-manager --set-enabled crb` |
| `/etc/sysctl.d/` setting reverts after reboot | `tuned-adm verify; tuned-adm active` | Active `tuned` profile overriding the same sysctl key | Override in custom `/etc/tuned/` profile inheriting base |
| Static IP lost after reboot | `nmcli connection show` | Configured via `ip addr` or wrong NetworkManager profile active | Persist via `nmcli connection modify` + `autoconnect yes` |
| `dnf` hangs or metadata errors on mirrors | `dnf clean all && dnf makecache` | Stale mirror metadata or broken DNS/IPv6 mirror | `dnf clean all`; verify `resolvectl` / `ip route` |

## SELinux Denial Diagnosis and Resolution

Follow this exact 4-step hierarchy instead of disabling SELinux:

`[ROOT]`
```bash
# 1. Inspect raw AVC denials from the last 10 minutes
ausearch -m AVC,USER_AVC -ts recent

# 2. Generate plain-English root cause analysis and exact remediation commands
sealert -a /var/log/audit/audit.log | tail -n 60

# 3. Check file contexts on the target path and running process domain
ls -lZ /srv/www/index.html
ps -eZ | grep -E 'nginx|httpd|postgres'
```

Apply fixes in order of safety (most preferred first):
1. **File label mismatch:** Register persistent rule via `semanage fcontext -a -t <type> '<regex>'` and run `restorecon -Rv <path>`.
2. **Non-standard port:** Register via `semanage port -a -t <port_type> -p tcp <port>`.
3. **Feature toggle (boolean):** Search with `semanage boolean -l | grep <service>` and enable with `setsebool -P <boolean> on`.
4. **Custom local policy module (last resort):** Review the exact rule with `audit2allow -w -a` before compiling:
   `[ROOT]`
   ```bash
   ausearch -m AVC -ts recent | audit2allow -M local_myapp
   cat local_myapp.te   # ALWAYS inspect generated rules before loading!
   semodule -i local_myapp.pp
   ```

> **Watch out:** Some SELinux denials are suppressed by `dontaudit` rules and never appear in `ausearch`. If a daemon fails mysteriously while `ausearch` is empty and temporarily setting `semanage permissive -a <domain>` fixes it, disable `dontaudit` briefly (`semodule -DB`), reproduce the failure, inspect `ausearch -m AVC -ts recent`, and immediately re-enable `dontaudit` (`semodule -B`) so audit logs do not flood disk.

## DNF and RPM Database Recovery

### Resolve Stale Metadata, Broken Mirrors, or Duplicate Packages

`[ROOT]`
```bash
# Clear cached repo metadata and rebuild cache
dnf clean all
dnf makecache --refresh

# Check for duplicate packages left by an interrupted upgrade
dnf check --duplicates

# Remove older duplicates if a transaction crashed mid-run
dnf remove --duplicates
```

### Rebuild a Corrupted RPM Database

If `rpm` or `dnf` throws SQLite/BDB database corruption errors:

`[ROOT]`
```bash
cp -a /var/lib/rpm /var/lib/rpm.bak
rpm --rebuilddb
dnf check
```

## firewalld and NetworkManager Debugging

### Trace Blocked Traffic in firewalld

`[ROOT]`
```bash
# Confirm active zone for each NIC and all rules in that zone
firewall-cmd --get-active-zones
firewall-cmd --list-all-zones | sed -n '/(active)/,/^$/p'

# Enable drop logging temporarily and watch kernel rejections live
firewall-cmd --set-log-denied=all
journalctl -k -f --grep='FINAL_REJECT|STATE_INVALID_DROP|FILTER_IN_DROP'

# Return log-denied to unicast or off once done
firewall-cmd --set-log-denied=unicast
```

### Debug NetworkManager Activation Failures

`[ROOT]`
```bash
# Inspect NetworkManager logs for the failing connection
journalctl -u NetworkManager -b --no-pager | tail -n 60

# Inspect exact keyfile contents and permissions (must be 0600 root:root)
ls -la /etc/NetworkManager/system-connections/
nmcli -f all connection show ens18 | grep -E 'ipv4|connection.autoconnect|general.state'
```

> **Watch out:** If two NetworkManager profiles exist for the same NIC (e.g., `System eth0` and a newly created `static-eth0`) both with `autoconnect yes`, rebooting can activate the wrong profile depending on `connection.autoconnect-priority`. Delete unused profiles cleanly with `nmcli connection delete "<old-profile>"`.

## Performance and tuned Drift Triage

When a kernel parameter in `/etc/sysctl.d/` does not match expectations after reboot, inspect both `sysctl` precedence and `tuned`:

`[ROOT]`
```bash
# Show which sysctl file sets a specific key (last file wins)
grep -rn 'vm.swappiness' /usr/lib/sysctl.d/ /etc/sysctl.d/ /etc/sysctl.conf /usr/lib/tuned/ /etc/tuned/ 2>/dev/null

# Verify live settings against the active tuned profile
tuned-adm active
tuned-adm verify
grep -i error /var/log/tuned/tuned.log | tail -n 20
```

## High-Signal One-Liners

```bash
# List recent SELinux denials summarized by source domain, target type, and class [ROOT]
ausearch -m AVC -ts today | audit2allow -w | tail -n 40

# Identify running services that must be restarted after RPM library updates [ROOT]
needs-restarting -s

# Check if the host requires a reboot for a newly installed kernel or glibc [NON-ROOT]
needs-restarting -r; echo "Exit code: $?"

# Show every local SELinux customization (ports, fcontexts, booleans) [ROOT]
semanage export

# Verify RPM package file integrity for a critical daemon (no output = clean) [ROOT]
rpm -V openssh-server systemd

# View full effective nftables firewalld ruleset with packet counters [ROOT]
nft list table inet firewalld
```
