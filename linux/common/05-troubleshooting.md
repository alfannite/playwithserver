# Linux Common Troubleshooting

Cross-distro diagnostic playbooks covering systemd failures, networking and DNS breakage, disk and inode exhaustion, OOM triage, and high-signal recovery one-liners.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Symptom to Fix Matrix](#symptom-to-fix-matrix)
- [Boot and systemd Service Failures](#boot-and-systemd-service-failures)
- [Network and DNS Diagnostics](#network-and-dns-diagnostics)
- [Disk, Inode, and Mount Recovery](#disk-inode-and-mount-recovery)
- [CPU, Memory, and OOM Triage](#cpu-memory-and-oom-triage)
- [High-Signal One-Liners](#high-signal-one-liners)

## Symptom to Fix Matrix

| Symptom | First Diagnostic Command | Common Root Cause | Targeted Fix |
| :--- | :--- | :--- | :--- |
| Service fails immediately on start | `journalctl -xeu <svc> --no-pager` | Config typo, missing dir, port conflict, bad permissions | Fix config/perms; check port with `ss -tulnp`; `systemctl restart <svc>` |
| `No space left on device` with free GBs | `df -ih` | Inode exhaustion (millions of tiny cache/session files) | Locate dense dir with `find`, purge stale files |
| `df -h` shows 100% but `du` shows less | `lsof +L1` | Deleted log files still held open by a running daemon | `systemctl reload` or `truncate -s 0 /proc/<pid>/fd/<fd>` |
| Host drops to emergency shell on boot | `journalctl -xb -p err` | Missing non-root disk in `/etc/fstab` without `nofail` | Mount root RW, add `nofail` to `/etc/fstab`, reboot |
| Slow SSH login (10-30s delay) | `ssh -vvv user@host` | Reverse DNS lookup or broken `GSSAPIAuthentication` | Set `UseDNS no` and `GSSAPIAuthentication no` in sshd |
| Sudden process disappearance (`Exit 137`) | `dmesg -T \| grep -iE 'oom\|killed'` | Linux OOM killer terminated highest `oom_score` process | Add RAM/swap, tune service `MemoryMax`, fix memory leak |
| DNS works by IP, fails by hostname | `resolvectl status; dig @1.1.1.1 host` | Broken stub resolver `/etc/resolv.conf` or firewall blocking UDP/53 | Restart `systemd-resolved` or fix DNS server config |
| `Too many open files` (`EMFILE`) | `prlimit --pid <PID>` | Default `RLIMIT_NOFILE` (1024) exceeded | Add `LimitNOFILE=65536` in `systemctl edit <svc>` |

## Boot and systemd Service Failures

### Triage a Failing Service

`[ROOT]`
```bash
# 1. Check unit state, exit code, and recent log lines
systemctl status myapp.service --no-pager -l

# 2. Pull full logs from the current boot for that unit
journalctl -u myapp.service -b --no-pager

# 3. Verify unit syntax and effective drop-ins
systemd-analyze verify /etc/systemd/system/myapp.service
systemctl cat myapp.service
```

### Triage Slow Boots or Previous-Boot Crashes

`[ROOT]`
```bash
# List recorded boots (0 = current, -1 = previous)
journalctl --list-boots

# Read the final 100 lines before the last crash or hard reboot
journalctl -b -1 -n 100 --no-pager

# Inspect kernel errors from the previous boot
journalctl -k -b -1 -p warning --no-pager

# Identify services blocking boot completion
systemd-analyze critical-chain
```

> **Watch out:** If `systemctl status` shows `code=killed, status=9/KILL`, do not assume a manual `kill -9`. Check both kernel OOM (`dmesg -T | grep -i oom`) and systemd cgroup memory limits (`systemctl show <svc> -p MemoryCurrent,MemoryMax`) as well as `TimeoutStartSec` / `TimeoutStopSec` expirations.

## Network and DNS Diagnostics

Follow bottom-up layer isolation: Link -> IP/Route -> Socket -> Firewall -> DNS.

`[ROOT]`
```bash
# Layer 1-2: Interface UP state, carrier, and RX/TX drops
ip -br -c link show
ip -s link show dev eth0

# Layer 3: IP address, default route, and path decision to target
ip -br -c addr show
ip route get 8.8.8.8

# Layer 4: Confirm service is bound to 0.0.0.0/:: (not just 127.0.0.1)
ss -tulnp | grep -E '(:80|:443|:5432)'

# Layer 4-5: Test raw TCP reachability with 3-second timeout
timeout 3 bash -c '</dev/tcp/10.0.0.20/5432' && echo "OPEN" || echo "CLOSED/FILTERED"

# Layer 7: Check DNS resolution path
resolvectl status
ls -la /etc/resolv.conf
dig +time=2 +tries=1 example.com
```

Inspect active nftables/iptables packet counters when traffic drops silently:

`[ROOT]`
```bash
nft list ruleset | head -n 80
iptables -L -n -v --line-numbers
```

## Disk, Inode, and Mount Recovery

### Reclaim Space Held by Deleted Open Files

When `df -h` shows 100% usage but `du -sh /*` cannot find the missing space, an application is still writing to an unlinked file.

`[ROOT]`
```bash
# List deleted files still held open by processes, sorted by size
lsof +L1 | sort -k7 -rn | head -n 20
```

Reload or restart the owning service cleanly so it opens a fresh log file. If the daemon cannot be restarted immediately, truncate the open descriptor safely:

`[ROOT]`
```bash
# Inspect descriptor path first
ls -l /proc/<PID>/fd/<FD>
# Truncate open file descriptor to zero bytes
: > /proc/<PID>/fd/<FD>
```

### Diagnose Read-Only Filesystem Remounts

If writes fail with `Read-only file system`, the kernel detected filesystem corruption or underlying storage/hypervisor I/O errors.

`[ROOT]`
```bash
# Confirm ro mount state
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS | grep -E '\bro\b'

# Check kernel storage and filesystem errors
dmesg -T | grep -iE 'ext4|xfs|i/o error|readonly|blk_update_request|nvme|scsi' | tail -n 40
```

> **Watch out:** Never run `fsck` on a mounted read-write filesystem; it causes severe metadata corruption. Unmount the data partition first (`umount /srv/data && fsck -f /dev/vg_data/lv_data`), or for the root filesystem trigger an offline check at next boot (`touch /forcefsck` or boot with kernel parameter `fsck.mode=force`).

### Find Inode-Heavy Directories

`[ROOT]`
```bash
df -ih
find /var -xdev -printf '%h\n' 2>/dev/null | sort | uniq -c | sort -rn | head -n 15
```

## CPU, Memory, and OOM Triage

### 60-Second Performance Triage (USE Method)

Run in sequence during live latency spikes:

`[ROOT]`
```bash
uptime                                # 1/5/15m load averages vs core count (nproc)
dmesg -T | tail -n 25                 # Hardware, OOM, or kernel errors
vmstat 1 5                            # r (run queue), si/so (swap thrash), wa (I/O wait), st (VM steal)
mpstat -P ALL 1 3 2>/dev/null || true # Per-CPU saturation (sysstat package)
free -h                               # Available memory vs buffers/cache/swap
ps -eo pid,ppid,user,%cpu,%mem,stat,comm --sort=-%cpu | head -n 15
ps -eo pid,ppid,user,%cpu,%mem,rss,comm --sort=-%mem | head -n 15
```

Interpret key `vmstat` columns:
- High `wa` (>20%) with high load: Disk/storage I/O bottleneck, not CPU exhaustion. Check `iostat -xz 1` or `iotop`.
- High `st` (>5%): Hypervisor CPU contention ("steal time") from noisy neighbors on the host.
- Non-zero sustained `si`/`so`: Active swap thrashing; memory pressure is actively degrading latency.
- Processes in `D` state (`ps aux | awk '$8 ~ /D/'`): Uninterruptible sleep waiting on disk or stale NFS mount; `kill -9` cannot terminate `D`-state processes until I/O resolves or times out.

### Inspect OOM Killer Events

`[ROOT]`
```bash
dmesg -T | grep -iE 'out of memory|killed process|oom-kill'
journalctl -k --grep='oom-kill|Out of memory' --no-pager
```

## High-Signal One-Liners

```bash
# Top 10 directories consuming space on root without crossing mounts [ROOT]
du -xhd1 / 2>/dev/null | sort -hr | head -n 10

# Count TCP connections grouped by state [NON-ROOT]
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn

# Top 10 remote IPs connected to port 443 [NON-ROOT]
ss -tn state established '( sport = :443 )' | awk 'NR>1 {print $4}' | rev | cut -d: -f2- | rev | sort | uniq -c | sort -rn | head -n 10

# Check which process is holding an unmountable directory busy [ROOT]
fuser -vm /mnt/backups

# Find processes currently in uninterruptible sleep (D state) [NON-ROOT]
ps -eo pid,stat,wchan:32,comm | awk '$2 ~ /D/'

# Test TLS certificate expiration on a local or remote endpoint [NON-ROOT]
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null | openssl x509 -noout -dates -subject
```
