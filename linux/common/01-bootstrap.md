# Linux Common Bootstrap

Cross-distro first-boot configuration covering host identity, persistent journald logging, NTP time sync, resilient `/etc/fstab` mounts, baseline `sysctl` tuning, and initial SSH access.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Hostname, Locale, and Timezone](#hostname-locale-and-timezone)
- [Persistent systemd Journal](#persistent-systemd-journal)
- [Time Synchronization](#time-synchronization)
- [Storage and fstab Mounts](#storage-and-fstab-mounts)
- [Baseline Kernel Parameters with sysctl](#baseline-kernel-parameters-with-sysctl)
- [Admin User and SSH Access](#admin-user-and-ssh-access)

## Hostname, Locale, and Timezone

Set a deterministic FQDN, UTC timezone, and UTF-8 locale before installing services or generating TLS certificates. Servers should run in `UTC` so log correlation across regions never shifts during daylight saving transitions.

`[ROOT]`
```bash
hostnamectl set-hostname prod-app-01.internal.example.com
timedatectl set-timezone UTC
localectl set-locale LANG=en_US.UTF-8
```

Ensure `/etc/hosts` resolves the short hostname and FQDN locally so `sudo` and Java/JVM services do not stall waiting on DNS timeouts.

`[ROOT]`
```bash
cat <<'EOF' > /etc/hosts
127.0.0.1   localhost
127.0.1.1   prod-app-01.internal.example.com prod-app-01
::1         localhost ip6-localhost ip6-loopback
EOF
```

Verify identity and clock state:

`[NON-ROOT]`
```bash
hostnamectl status
timedatectl status
```

## Persistent systemd Journal

Several minimal server images default to volatile journal storage (`/run/log/journal`), losing all boot logs after a crash or power cycle. Configure bounded persistent storage under `/var/log/journal` using a drop-in file instead of editing `/etc/systemd/journald.conf` directly.

`[ROOT]`
```bash
mkdir -p /etc/systemd/journald.conf.d /var/log/journal

cat <<'EOF' > /etc/systemd/journald.conf.d/99-persistent.conf
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=1G
SystemKeepFree=2G
MaxRetentionSec=30day
RateLimitIntervalSec=30s
RateLimitBurst=10000
EOF

systemctl restart systemd-journald
journalctl --disk-usage
```

| Parameter | Purpose | Recommended Server Value |
| :--- | :--- | :--- |
| `Storage` | Keep logs across reboots | `persistent` |
| `SystemMaxUse` | Hard cap on `/var/log/journal` disk consumption | `1G` to `4G` |
| `SystemKeepFree` | Minimum free space preserved on `/var` | `2G` |
| `MaxRetentionSec` | Auto-expire old entries | `30day` |
| `RateLimitBurst` | Prevent chatty daemons from hiding crash logs | `10000` |

> **Watch out:** Never run `rm -rf /var/log/journal/*` to reclaim disk space while `systemd-journald` is running; deleted open file descriptors stay allocated until restart and can corrupt active journal files. Always use `journalctl --vacuum-size=500M` or `journalctl --vacuum-time=7d`.

## Time Synchronization

Accurate clocks are mandatory for Kerberos, TLS certificate validation, distributed databases, and Raft consensus. Prefer `chronyd` over `systemd-timesyncd` on servers because `chrony` handles VM clock drift, asymmetric networks, and rapid slewing without stepping time backward.

Verify active NTP daemon and synchronization status:

`[NON-ROOT]`
```bash
# If using chrony (RHEL/Rocky/Alma, Proxmox, configured Debian/Ubuntu)
chronyc tracking
chronyc sources -v

# If using systemd-timesyncd (default minimal Debian/Ubuntu)
timedatectl timesync-status
```

Ensure only one NTP client is enabled so two daemons do not fight over clock adjustments:

`[ROOT]`
```bash
systemctl disable --now systemd-timesyncd 2>/dev/null || true
systemctl enable --now chronyd 2>/dev/null || systemctl enable --now chrony
```

## Storage and fstab Mounts

Always mount secondary block devices by `UUID` or `PARTUUID` rather than `/dev/sdb1`, because device letters change when disks are added, removed, or reordered by the hypervisor or HBA.

### Inspect Block Devices and UUIDs

`[NON-ROOT]`
```bash
lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS,MODEL
blkid
```

### Resilient fstab Entries

Use `nofail` on non-root data disks and `x-systemd.automount` on network mounts (NFS/SMB) so an unreachable disk or NAS never drops the host into emergency mode during boot.

`[ROOT]`
```bash
# /etc/fstab examples

# Local ext4 data disk (non-blocking if detached)
UUID=8f9c2a1b-4d3e-4b2a-9f1e-1234567890ab  /srv/data  ext4  defaults,noatime,nofail,x-systemd.device-timeout=15s  0  2

# Local XFS data disk
UUID=3c7d1e5a-9b8f-4c6d-8e2a-0987654321fe  /var/lib/containers  xfs  defaults,noatime,nofail,x-systemd.device-timeout=15s  0  0

# NFSv4 share mounted on demand with timeout protection
10.10.20.5:/export/backups  /mnt/backups  nfs4  _netdev,nofail,noatime,soft,timeo=50,retrans=3,x-systemd.automount,x-systemd.idle-timeout=300  0  0
```

Validate `/etc/fstab` before rebooting:

`[ROOT]`
```bash
systemctl daemon-reload
findmnt --verify --verbose
mount -a
```

> **Watch out:** Running `mount -a` alone does not catch syntax errors that break `systemd-fstab-generator` on boot, nor does it refresh generated `.mount` units after editing `/etc/fstab`. Always run `systemctl daemon-reload` and `findmnt --verify` after every `/etc/fstab` change.

## Baseline Kernel Parameters with sysctl

Never edit `/etc/sysctl.conf` directly on modern distributions; drop numbered files into `/etc/sysctl.d/` so package upgrades never prompt for merges and load order stays explicit.

`[ROOT]`
```bash
cat <<'EOF' > /etc/sysctl.d/90-server-baseline.conf
# Enable BBR congestion control with FQ queueing discipline
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Increase socket and connection queues for busy hosts
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192

# Avoid aggressive swapping on servers with RAM headroom
vm.swappiness = 10

# Raise inotify limits for containers, log shippers, and systemd
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
EOF

sysctl --system
```

Verify active values:

`[NON-ROOT]`
```bash
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc vm.swappiness fs.inotify.max_user_watches
```

## Admin User and SSH Access

Create a dedicated administrative user with SSH key authentication and verify `sudo` works before disabling root password logins.

`[ROOT]`
```bash
# Use "sudo" group on Debian/Ubuntu, "wheel" group on RHEL/Rocky/Alma/Fedora
ADMIN_GROUP="$(getent group wheel >/dev/null && echo wheel || echo sudo)"
useradd -m -s /bin/bash -G "${ADMIN_GROUP}" opsadmin
passwd opsadmin

install -d -m 0700 -o opsadmin -g opsadmin /home/opsadmin/.ssh
install -m 0600 -o opsadmin -g opsadmin /dev/null /home/opsadmin/.ssh/authorized_keys
# Append your public key:
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePublicKeyReplaceMe ops@workstation' >> /home/opsadmin/.ssh/authorized_keys
```

Validate SSH syntax and test login in a second terminal before closing your active root session:

`[ROOT]`
```bash
sshd -t
```
