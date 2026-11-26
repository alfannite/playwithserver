# Linux Common Tips and Tricks

Production-tested workflows for systemd drop-ins and timers, kernel/network `sysctl` tuning, LVM/ZFS operations, resilient `rsync`/`tmux` patterns, and fast shell triage.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [systemd Drop-Ins and Timers](#systemd-drop-ins-and-timers)
- [Kernel and Network Tuning via sysctl](#kernel-and-network-tuning-via-sysctl)
- [LVM and ZFS Operational Patterns](#lvm-and-zfs-operational-patterns)
- [Resilient rsync and tmux Workflows](#resilient-rsync-and-tmux-workflows)
- [Shell and Process Shortcuts](#shell-and-process-shortcuts)

## systemd Drop-Ins and Timers

### Safe Service Overrides with Drop-Ins

Never edit packaged unit files in `/usr/lib/systemd/system/`; package updates overwrite them silently. Use drop-ins under `/etc/systemd/system/<unit>.d/override.conf` via `systemctl edit`.

`[ROOT]`
```bash
systemctl edit nginx.service
```

Example override adding auto-restart, higher file descriptor limits, and CPU/memory guardrails:

```ini
[Service]
# Clear an existing directive before replacing it (required for ExecStart)
# ExecStart=
# ExecStart=/usr/sbin/nginx -g 'daemon off;'

Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
MemoryHigh=1500M
MemoryMax=2G
CPUQuota=200%
```

Verify effective merged configuration:

`[NON-ROOT]`
```bash
systemctl cat nginx.service
systemctl show nginx.service -p LimitNOFILE,MemoryHigh,MemoryMax,Restart
```

### Replace cron with systemd Timers

Unlike `cron`, `systemd` timers capture stdout/stderr automatically in `journalctl`, prevent overlapping runs natively, support randomized jitter (`RandomizedDelaySec`) to avoid thundering herds, and catch up missed runs after downtime (`Persistent=true`).

| Capability | `cron` | `systemd` Timer |
| :--- | :--- | :--- |
| Overlap prevention | Manual (`flock`) | Native (won't re-trigger while service is active) |
| Structured logging | Requires mail/redirects | Automatic in `journalctl -u <name>` |
| Missed-run catchup | Requires `anacron` | `Persistent=true` |
| Resource limits / sandboxing | Manual wrapper | Full `MemoryMax`, `User=`, `ProtectSystem=` |
| Sub-minute precision | No (1 min minimum) | Yes (`OnUnitActiveSec=15s`) |

Create a backup job service and daily timer with jitter:

`[ROOT]`
```bash
cat <<'EOF' > /etc/systemd/system/db-backup.service
[Unit]
Description=Nightly database backup
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=backup
ExecStart=/usr/local/bin/db-backup.sh
Nice=10
IOSchedulingClass=idle
EOF

cat <<'EOF' > /etc/systemd/system/db-backup.timer
[Unit]
Description=Run nightly database backup

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now db-backup.timer
systemctl list-timers --all
```

Test `OnCalendar` expressions before deploying:

`[NON-ROOT]`
```bash
systemd-analyze calendar --iterations=5 "Mon..Fri *-*-* 03:15:00"
```

> **Watch out:** Do not enable the `.service` unit of a timer (`systemctl enable db-backup.service`); only enable the `.timer` unit. Also note that `OnCalendar=` uses the system timezone unless `UTC` is appended explicitly.

## Kernel and Network Tuning via sysctl

### High-Throughput and High-Connection Workloads

Apply targeted tuning for reverse proxies, load balancers, and Kubernetes nodes in `/etc/sysctl.d/95-network-tuning.conf`:

`[ROOT]`
```bash
cat <<'EOF' > /etc/sysctl.d/95-network-tuning.conf
# BBR + FQ improves throughput over lossy/high-latency links
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Expand ephemeral port range for high outbound connection rates
net.ipv4.ip_local_port_range = 10240 65535

# Reuse TIME-WAIT sockets safely for outbound connections
net.ipv4.tcp_tw_reuse = 1

# Raise conntrack table size (requires nf_conntrack module loaded)
net.netfilter.nf_conntrack_max = 262144

# Tune dirty page writeback to prevent I/O stalls on high-RAM hosts
vm.dirty_background_bytes = 67108864
vm.dirty_bytes = 268435456
EOF

sysctl --system
```

Verify conntrack utilization vs. limit:

`[NON-ROOT]`
```bash
sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```

> **Watch out:** Never set `net.ipv4.tcp_tw_recycle = 1` (removed in Linux 4.12 and broken behind NAT) and avoid blindly setting `vm.swappiness = 0` on kernels >= 3.5, which disables swapping almost entirely and increases the risk of sudden OOM kills instead of gracefully paging out cold anonymous memory. Use `vm.swappiness = 1` or `10`.

## LVM and ZFS Operational Patterns

### Online LVM Thin Provisioning Inspection and Auto-Extend

Configure `/etc/lvm/lvm.conf` so thin pools and snapshots automatically expand before hitting 100% exhaustion:

`[ROOT]`
```bash
grep -E 'thin_pool_autoextend|snapshot_autoextend' /etc/lvm/lvm.conf
# Recommended values under activation {}:
# snapshot_autoextend_threshold = 80
# snapshot_autoextend_percent = 20
# thin_pool_autoextend_threshold = 80
# thin_pool_autoextend_percent = 20
```

### ZFS Dataset Tuning for Databases and Containers

Match `recordsize` to workload block size and enable `lz4` (or `zstd`) compression with `atime=off` on every ZFS dataset:

`[ROOT]`
```bash
# General-purpose dataset
zfs set compression=lz4 atime=off xattr=sa dnodesize=auto tank/data

# PostgreSQL dataset (8K pages, disable redundant full-page writes only when logbias/recordsize are tuned)
zfs create -o recordsize=8K -o compression=lz4 -o atime=off -o logbias=throughput tank/pgdata

# Cap ZFS ARC memory usage on mixed-workload hosts (e.g., 4 GiB max)
echo "options zfs zfs_arc_max=4294967296" > /etc/modprobe.d/zfs.conf
```

> **Watch out:** Changing `zfs_arc_max` in `/etc/modprobe.d/zfs.conf` requires updating the initramfs (`update-initramfs -u` on Debian/Ubuntu or `dracut -f` on RHEL-family) and rebooting, or applying it live via `echo 4294967296 > /sys/module/zfs/parameters/zfs_arc_max`.

## Resilient rsync and tmux Workflows

### Fast Atomic-Style Directory Sync Over SSH

For trusted LAN transfers where SSH encryption is the CPU bottleneck, use `aes128-gcm@openssh.com` and disable `rsync` compression (`-z`) on already-compressed media or gigabit LANs:

`[NON-ROOT]`
```bash
rsync -aHAX --numeric-ids --info=progress2 \
  -e "ssh -T -c aes128-gcm@openssh.com -o Compression=no" \
  /srv/backups/ ops@10.10.10.20:/srv/backups/
```

### Safe Live Editing in tmux Across Multiple Hosts

Configure `~/.tmux.conf` with a generous scrollback buffer, mouse support, and visual pane synchronization indicator:

`[NON-ROOT]`
```tmux
set -g history-limit 50000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g status-right '#{?pane_synchronized,#[bg=red fg=white bold] SYNC ON ,} %Y-%m-%d %H:%M UTC'
bind S setw synchronize-panes
```

Press `Ctrl-b` then `S` to toggle typing across all panes in a window simultaneously; the red `SYNC ON` banner prevents accidental multi-host commands.

## Shell and Process Shortcuts

### Run One-Off Background Jobs Under systemd

Instead of `nohup ... &`, launch long-running ad-hoc jobs as transient systemd units so they get clean logging, cgroup isolation, and survival across SSH disconnects:

`[ROOT]`
```bash
systemd-run --unit=rebalance-job --description="One-off data sync" \
  -p MemoryMax=2G -p CPUQuota=100% \
  /usr/bin/rsync -aHAX /srv/src/ /srv/dst/

# Monitor progress
systemctl status rebalance-job
journalctl -u rebalance-job -f
```

### Zero-Noise Config Viewing and Fast Process Inspection

`[NON-ROOT]`
```bash
# Strip blank lines and comments from any config file
grep -Ev '^\s*(#|$)' /etc/ssh/sshd_config

# Show exact open files and listening sockets of a running PID
ls -l /proc/<PID>/fd

# Inspect live environment variables of a running daemon [ROOT]
tr '\0' '\n' < /proc/<PID>/environ

# Find the largest 15 files on the root filesystem without crossing mount points [ROOT]
find / -xdev -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -n 15 | numfmt --to=iec-i
```
