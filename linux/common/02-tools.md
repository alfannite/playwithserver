# Linux Common Essential Tools

Core cross-distro CLI tools for systemd, logging, modern networking, storage, synchronization, and terminal sessions with install commands, high-signal flags, and operational edge cases.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Quick Reference Matrix](#quick-reference-matrix)
- [Service and Log Management](#service-and-log-management)
- [Modern Networking](#modern-networking)
- [Storage and Filesystems](#storage-and-filesystems)
- [Sync and Terminal Multiplexing](#sync-and-terminal-multiplexing)
- [Process and Resource Inspection](#process-and-resource-inspection)

## Quick Reference Matrix

| Category | Modern Tool | Replaces (Legacy) | Primary Purpose |
| :--- | :--- | :--- | :--- |
| Init & Services | `systemctl`, `systemd-analyze` | `service`, `chkconfig` | Unit lifecycle, drop-ins, timers, boot profiling |
| Logging | `journalctl` | `tail /var/log/syslog` | Structured binary logs by unit, boot, and priority |
| Interfaces & Routes | `ip` (`iproute2`) | `ifconfig`, `route`, `arp` | Links, IPv4/IPv6 addresses, routing, neighbor tables |
| Sockets | `ss` (`iproute2`) | `netstat` | TCP/UDP/UNIX sockets, PIDs, kernel socket states |
| DNS Inspection | `resolvectl`, `dig` | `nslookup` | systemd-resolved per-link DNS, direct resolver queries |
| Block & Mounts | `lsblk`, `findmnt` | `fdisk -l`, `mount` | Block topology, UUIDs, active mount hierarchy |
| Volumes | `lvm2`, `zfs` | Static partitions | Online snapshots, thin provisioning, checksummed storage |
| File Sync | `rsync` | `scp`, `cp -r` | Delta transfers, ACL/xattr preservation, resumable sync |
| Sessions | `tmux` | `screen` | Persistent remote sessions, panes, synchronized input |

## Service and Log Management

### systemctl and systemd-analyze

Pre-installed on all systemd-based Linux distributions (`systemd` package).

```bash
# List only failed units across the host [NON-ROOT]
systemctl --failed

# Show active unit file plus all drop-in overrides [NON-ROOT]
systemctl cat nginx.service

# Create a safe persistent override without editing /usr/lib/systemd/system [ROOT]
systemctl edit nginx.service

# Inspect boot time breakdown and slow units [NON-ROOT]
systemd-analyze blame | head -n 20
systemd-analyze critical-chain
```

> **Watch out:** Running `systemctl restart` on a unit whose file was modified on disk silently uses the old unit definition until `systemctl daemon-reload` is run. `systemctl edit` reloads automatically on save, while manual edits under `/etc/systemd/system/` do not.

### journalctl

Pre-installed with `systemd`.

```bash
# Follow logs for a specific service with real timestamps [NON-ROOT]
journalctl -u postgresql.service -f -o short-iso

# Inspect errors (priority 3/err and above) from the previous boot [NON-ROOT]
journalctl -b -1 -p err --no-pager

# Filter logs across a time window and multiple units [NON-ROOT]
journalctl -u nginx -u php8.2-fpm --since "2026-01-15 02:00:00" --until "2026-01-15 02:30:00"

# Reclaim disk space safely [ROOT]
journalctl --vacuum-size=500M
```

> **Watch out:** Non-root users only see their own user journal unless added to the `systemd-journal` group (`usermod -aG systemd-journal opsadmin`). Running `journalctl -u ssh` as an unprivileged user without that group returns an empty output rather than a permission error.

## Modern Networking

### ip (iproute2)

Install if missing (usually pre-installed):

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y iproute2
# RHEL/Rocky/Alma/Fedora
dnf install -y iproute
```

Usage:

```bash
# Compact colored interface and IP overview [NON-ROOT]
ip -br -c addr show

# Show routing table and trace exact route chosen for a destination IP [NON-ROOT]
ip -c route show
ip route get 1.1.1.1

# Inspect ARP/NDP neighbor cache [NON-ROOT]
ip -c neigh show

# Show packet drops and RX/TX errors per interface [NON-ROOT]
ip -s -s link show dev eth0
```

> **Watch out:** Changes made with `ip addr add` or `ip route add` are strictly runtime-only and disappear on reboot or network manager reload. Always persist networking via `netplan`, `nmcli`, `systemd-networkd`, or `/etc/network/interfaces`.

### ss (Socket Statistics)

Included in `iproute2` / `iproute`.

```bash
# Show all listening TCP and UDP ports with owning PID and process name [ROOT]
ss -tulnp

# Show established TCP connections with kernel timers and congestion algorithm [NON-ROOT]
ss -ti state established

# Filter sockets by destination port or subnet [NON-ROOT]
ss -tan '( dport = :443 or sport = :443 )'

# Summary of socket counts by state (detect TIME-WAIT or SYN-RECV floods) [NON-ROOT]
ss -s
```

> **Watch out:** Running `ss -tulnp` without root privileges omits the `users:(("process",pid=...))` column for sockets owned by other users. Prefix with `sudo` whenever identifying which daemon holds a port.

### resolvectl and dig

Install `dig` (`dnsutils` on Debian/Ubuntu, `bind-utils` on RHEL-family):

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y dnsutils
# RHEL/Rocky/Alma/Fedora
dnf install -y bind-utils
```

Usage:

```bash
# Show active DNS servers, domains, and DNSSEC status per interface [NON-ROOT]
resolvectl status

# Test resolution through systemd-resolved cache and split-DNS rules [NON-ROOT]
resolvectl query api.internal.example.com

# Flush systemd-resolved DNS cache after record changes [ROOT]
resolvectl flush-caches

# Bypass local stub resolver and query an upstream DNS server directly [NON-ROOT]
dig @1.1.1.1 example.com AAAA +short +stats
```

> **Watch out:** `dig` queries `/etc/resolv.conf` directly, which on `systemd-resolved` hosts points to `127.0.0.53`. If you query `@8.8.8.8`, you bypass split-DNS and VPN search domains; test both `resolvectl query` and `dig @<dns-server>` to isolate host vs. upstream DNS issues.

### tcpdump

Install:

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y tcpdump
# RHEL/Rocky/Alma/Fedora
dnf install -y tcpdump
```

Usage:

```bash
# Capture packets on any interface without DNS lookup (-nn) for port 5432 [ROOT]
tcpdump -i any -nn port 5432

# Capture SYN/FIN/RST TCP handshake anomalies on eth0 [ROOT]
tcpdump -i eth0 -nn 'tcp[tcpflags] & (tcp-syn|tcp-rst|tcp-fin) != 0'

# Write full-frame capture to disk with 100MB ring rotation (max 5 files) [ROOT]
tcpdump -i eth0 -nn -s 0 -C 100 -W 5 -w /tmp/capture.pcap port 443
```

> **Watch out:** Capturing on `-i any` uses Linux "cooked" capture headers (`SLL`) and disables promiscuous mode; switch to a specific interface (`-i eth0`) when inspecting VLAN tags (`vlan`) or MAC addresses.

## Storage and Filesystems

### lsblk and findmnt

Pre-installed via `util-linux`.

```bash
# Full block topology with filesystem, UUID, label, transport, and mountpoints [NON-ROOT]
lsblk -o NAME,MAJ:MIN,SIZE,TYPE,TRAN,FSTYPE,UUID,MOUNTPOINTS

# Display active mount tree including mount options and propagation [NON-ROOT]
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS

# Find which mountpoint serves a specific path [NON-ROOT]
findmnt -T /var/lib/docker

# Validate /etc/fstab syntax and UUID availability before reboot [ROOT]
findmnt --verify --verbose
```

> **Watch out:** `lsblk` reads cached udev metadata (`FSTYPE`, `UUID`). After `mkfs` or `wipefs`, run `udevadm settle` or pass `lsblk -f` after `partprobe` if fields appear blank.

### lvm2 (Logical Volume Manager)

Install:

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y lvm2
# RHEL/Rocky/Alma/Fedora
dnf install -y lvm2
```

Usage:

```bash
# Inspect physical volumes, volume groups, and logical volumes [ROOT]
pvs; vgs; lvs -o lv_name,vg_name,lv_size,lv_attr,data_percent,origin

# Extend a logical volume and grow its ext4/xfs filesystem online in one command [ROOT]
lvextend -r -L +20G /dev/vg_data/lv_app

# Extend using 100% of remaining free space in the VG [ROOT]
lvextend -r -l +100%FREE /dev/vg_data/lv_app

# Create a 5G copy-on-write snapshot before an upgrade [ROOT]
lvcreate -s -L 5G -n lv_app_snap /dev/vg_data/lv_app
```

> **Watch out:** Classic (thick) LVM snapshots become permanently invalid (`Invalid`) if written data exceeds the allocated snapshot size (`Data%` hits `100%`), which can also freeze or corrupt reads on the snapshot. Monitor `lvs` closely or configure `snapshot_autoextend_threshold = 80` in `/etc/lvm/lvm.conf`.

### ZFS (`zpool` and `zfs`)

Install (Debian/Proxmox uses `zfsutils-linux`; RHEL-family uses OpenZFS repo `zfs`):

`[ROOT]`
```bash
# Debian 12/13 (with contrib repo enabled) / Ubuntu
apt-get install -y zfsutils-linux
# RHEL/Rocky/Alma 9 (after adding OpenZFS release RPM)
dnf install -y https://zfsonlinux.org/epel/zfs-release-2-3$(rpm --eval "%{dist}").noarch.rpm
dnf install -y kernel-devel zfs
```

Usage:

```bash
# Check pool health, scrub status, and I/O errors [NON-ROOT]
zpool status -v
zpool iostat -v 2

# List datasets with compression ratio and actual referenced space [NON-ROOT]
zfs list -o name,used,avail,refer,compressratio,mountpoint

# Create a recursive atomic snapshot and send incrementally over SSH [ROOT]
zfs snapshot -r tank/data@2026-01-15
zfs send -R tank/data@2026-01-15 | ssh backup-host zfs recv -F backup/data
```

> **Watch out:** Never let a ZFS pool exceed 80-85% capacity; copy-on-write allocation switches from first-fit to best-fit and fragments severely, degrading write IOPS. Also set `ashift=12` (4K sectors) at `zpool create` time because `ashift` cannot be changed per-vdev later.

## Sync and Terminal Multiplexing

### rsync

Install:

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y rsync
# RHEL/Rocky/Alma/Fedora
dnf install -y rsync
```

Usage:

```bash
# Dry-run archive sync preserving ACLs, xattrs, hardlinks, and numeric UIDs [ROOT]
rsync -aHAX --numeric-ids --info=progress2 --dry-run /srv/data/ root@10.0.0.20:/srv/data/

# Resumable transfer over SSH with bandwidth cap (25 MB/s) [NON-ROOT]
rsync -avz --partial --append-verify --bwlimit=25M /backups/ ops@10.0.0.20:/backups/

# Mirror exact directory state deleting extraneous destination files [DESTRUCTIVE] [ROOT]
rsync -aHAX --numeric-ids --delete-delay /srv/app/ /mnt/replica/app/
```

> **Watch out:** A trailing slash on the source path (`/srv/data/`) copies the *contents* of the directory, whereas omitting it (`/srv/data`) creates `/dst/data/`. Always run `--dry-run --itemize-changes` (`-ni`) before combining `rsync` with `--delete`.

### tmux

Install:

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y tmux
# RHEL/Rocky/Alma/Fedora
dnf install -y tmux
```

Usage:

```bash
# Create or attach to a named persistent maintenance session [NON-ROOT]
tmux new-session -A -s maint

# List active sessions on the host [NON-ROOT]
tmux ls

# Send a command to a detached session non-interactively [NON-ROOT]
tmux send-keys -t maint 'journalctl -f -u nginx' C-m

# Detach cleanly inside tmux: press Ctrl-b then d
```

> **Watch out:** If `systemd-logind` has `KillUserProcesses=yes` configured in `/etc/systemd/logind.conf`, detached `tmux` sessions are killed on SSH logout unless user lingering is enabled (`loginctl enable-linger opsadmin`) or the session is launched via `systemd-run --scope --user tmux`.

## Process and Resource Inspection

### btop

Install:

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y btop
# RHEL/Rocky/Alma (EPEL) / Fedora
dnf install -y btop
```

Usage:

```bash
# Launch with 1-second refresh interval [NON-ROOT]
btop -u 1000

# Use TTY-safe ASCII mode over serial consoles or basic terminals [NON-ROOT]
btop --tty
```

> **Watch out:** Leaving `btop` or `htop` running at 100ms refresh inside an idle `tmux` pane on a single-vCPU VM can consume 5-10% CPU continuously due to `/proc` polling. Keep refresh rates at 1000ms or higher on production nodes.

### ncdu (Disk Usage Analyzer)

Install:

`[ROOT]`
```bash
# Debian/Ubuntu
apt-get install -y ncdu
# RHEL/Rocky/Alma (EPEL) / Fedora
dnf install -y ncdu
```

Usage:

```bash
# Scan root filesystem without crossing into NFS, /proc, or other mounts (-x) [ROOT]
ncdu -x /

# Export scan on a busy server to analyze offline later [ROOT]
ncdu -1xo- /var | gzip > /tmp/var-usage.json.gz
zcat /tmp/var-usage.json.gz | ncdu -f -
```

> **Watch out:** Always pass `-x` (one filesystem) when scanning `/`; without it, `ncdu` traverses mounted NFS shares, container overlay mounts, and `/proc/kcore`, stalling the scan or reporting phantom multi-terabyte sizes.
