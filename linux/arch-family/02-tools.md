# Arch Family Essential Tools

Categorized production and diagnostic toolchain for Arch Linux, EndeavourOS, and CachyOS with exact install commands, high-signal flags, and operational edge cases.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Tooling Matrix](#tooling-matrix)
- [Package and Repository Management](#package-and-repository-management)
- [System Performance and Process Diagnostics](#system-performance-and-process-diagnostics)
- [Networking and Packet Inspection](#networking-and-packet-inspection)
- [Storage and Filesystem Tools](#storage-and-filesystem-tools)
- [Boot, Kernel, and Journald Forensics](#boot-kernel-and-journald-forensics)

## Tooling Matrix

| Category | Tool | Package (`pacman` / AUR) | Primary Purpose |
| :--- | :--- | :--- | :--- |
| Package | `pacman` | `pacman` (preinstalled) | Core binary package manager and DB queries |
| Package | `paru` / `yay` | `paru-bin` / `yay-bin` (AUR) | AUR build/upgrade wrapper + repo search |
| Package | `paccache` / `pacdiff` | `pacman-contrib` | Cache retention pruning and `.pacnew` merging |
| Package | `reflector` | `reflector` | Mirrorlist filtering and speed ranking |
| Package | `downgrade` | `downgrade` (AUR) | Interactive rollback from local cache or ALA |
| Performance | `btop` | `btop` | CPU, memory, disk I/O, and network TUI |
| Performance | `iostat` / `pidstat` | `sysstat` | Block device latency and per-PID resource stats |
| Performance | `iotop` | `iotop-c` | Real-time per-process disk I/O profiler |
| Performance | `strace` | `strace` | System call and signal tracer |
| Network | `ss` / `ip` | `iproute2` | Socket state, routing, and interface control |
| Network | `tcpdump` | `tcpdump` | CLI packet capture and BPF filtering |
| Network | `mtr` | `mtr` | Continuous traceroute + packet loss monitor |
| Network | `bandwhich` | `bandwhich` | Live bandwidth usage mapped to PIDs |
| Storage | `ncdu` | `ncdu` | Interactive disk space analyzer |
| Storage | `smartctl` | `smartmontools` | NVMe/SATA SMART health and self-tests |
| Boot / Logs | `journalctl` / `systemd-analyze` | `systemd` (preinstalled) | Structured logs and boot-time profiling |
| Boot / Logs | `mkinitcpio` | `mkinitcpio` (preinstalled) | Initramfs image builder and inspector |

## Package and Repository Management

### `pacman`

Preinstalled core package manager (`pacman`).

```bash
# [ROOT] Full system upgrade
sudo pacman -Syu

# [NON-ROOT] Find which installed package owns a file
pacman -Qo /usr/bin/dig

# [NON-ROOT] Search which repo package provides a missing binary/library (refresh DB first with sudo pacman -Fy)
pacman -F libcrypto.so.3

# [NON-ROOT] List explicitly installed native packages (excluding dependencies and AUR)
pacman -Qqen

# [NON-ROOT] Verify installed package files against mtree metadata for tampering or corruption
sudo pacman -Qkk 2>&1 | grep -v '0 altered files'
```

> **Watch out:** Running `pacman -Rns <pkg>` removes unneeded dependencies and backs up modified config files, whereas `pacman -Rc <pkg>` cascades and removes packages that depend on `<pkg>`, which can wipe out half the desktop or system stack. Always inspect the removal list before confirming.

### `paru` (and `yay`)

Install from AUR (`paru-bin` or `yay-bin`) or preinstalled on CachyOS (`paru`) and EndeavourOS (`yay`).

```bash
# [NON-ROOT] Install paru-bin if not present
git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin && (cd /tmp/paru-bin && makepkg -si)

# [NON-ROOT] Upgrade official repo packages and AUR packages in one pass
paru -Syu

# [NON-ROOT] Print pending updates without modifying the system
paru -Qua

# [NON-ROOT] Search packages with AUR votes and out-of-date flags
paru -Ss wireguard

# [NON-ROOT] Clean cached AUR build directories
paru -Sc
```

> **Watch out:** Never pass `--noconfirm` blindly to AUR upgrades. AUR `PKGBUILD` files are community-maintained shell scripts executed during `makepkg`; inspect diffs in `paru`'s pager before building.

### `paccache` and `pacdiff`

Install via `pacman-contrib`:

```bash
# [ROOT] Install pacman-contrib
sudo pacman -S --needed pacman-contrib

# [ROOT] Dry-run cache cleanup keeping the 2 most recent versions of each installed package
paccache -dk2

# [ROOT] Remove cached versions of uninstalled packages completely, keep 2 versions of installed ones
sudo paccache -ruk0 && sudo paccache -rk2

# [ROOT] Scan for .pacnew/.pacsave files and merge interactively using vimdiff
sudo DIFFPROG="vim -d" pacdiff
```

> **Watch out:** Never blindly overwrite `/etc/shadow`, `/etc/passwd`, `/etc/group`, `/etc/gshadow`, or `/etc/fstab` with a `.pacnew` file. Overwriting `/etc/shadow` locks out every local account on the host.

### `reflector`

Install via `reflector`:

```bash
# [ROOT] Install reflector
sudo pacman -S --needed reflector

# [NON-ROOT] Preview ranked mirrors without overwriting /etc/pacman.d/mirrorlist
reflector --protocol https --latest 15 --sort rate --verbose

# [ROOT] Filter by IPv4 + HTTPS mirrors updated within 12 hours and write mirrorlist
sudo reflector --ipv4 --protocol https --age 12 --latest 20 --fastest 10 --sort rate --save /etc/pacman.d/mirrorlist
```

> **Watch out:** `reflector` fetches mirror status over HTTPS from `archlinux.org`. If DNS or outbound port 443 is broken on the server, `reflector` will fail; inspect `/etc/pacman.d/mirrorlist.pacnew` for static fallback URLs.

### `downgrade`

Install from AUR (`downgrade`) or CachyOS/EndeavourOS repos:

```bash
# [NON-ROOT] Install downgrade
paru -S downgrade

# [ROOT] Interactively downgrade a package from local cache or Arch Linux Archive (ALA)
sudo downgrade mesa

# [ROOT] Downgrade directly to a specific version without prompting
sudo downgrade 'openssl=3.3.1-1'
```

> **Watch out:** Downgrading a single core library (`glibc`, `icu`, `python`, `openssl`) creates a partial-upgrade state. Either downgrade the dependent packages together or roll back the entire system to a specific date via the Arch Linux Archive (`https://archive.archlinux.org/repos/YYYY/MM/DD/`).

## System Performance and Process Diagnostics

### `btop`

Install via `btop`:

```bash
# [ROOT] Install btop
sudo pacman -S --needed btop

# [NON-ROOT] Launch with 1-second refresh interval
btop -u 1000

# [NON-ROOT] Launch with TTY-safe ASCII graph mode over serial/minimal SSH
btop --tty_on
```

> **Watch out:** `btop` needs `CAP_SYS_PTRACE` or root privileges to display I/O stats for other users' processes, and GPU telemetry requires vendor libraries (`rocm-smi-lib` for AMD, `nvidia-utils` for NVIDIA).

### `sysstat` (`iostat`, `pidstat`, `mpstat`)

Install via `sysstat`:

```bash
# [ROOT] Install sysstat
sudo pacman -S --needed sysstat

# [NON-ROOT] Extended block device latency and queue depth every 2 seconds
iostat -xz 2

# [NON-ROOT] Per-process CPU, disk I/O, and context switches every 2 seconds
pidstat -urd 2

# [NON-ROOT] Per-core CPU utilization including steal time (critical on cloud VMs)
mpstat -P ALL 1
```

> **Watch out:** The first output block of `iostat`, `mpstat`, and `pidstat` is the cumulative average since boot, not current load. Always read from the second interval onward.

### `iotop-c`

Install via `iotop-c` (C rewrite with lower CPU overhead than Python `iotop`):

```bash
# [ROOT] Install iotop-c
sudo pacman -S --needed iotop-c

# [ROOT] Show only processes actively performing disk I/O
sudo iotop -o

# [ROOT] Batch mode logging accumulated I/O over 10 samples
sudo iotop -oPa -b -n 10
```

> **Watch out:** `iotop` requires `CONFIG_TASK_DELAY_ACCT` and `kernel.task_delayacct=1` for accurate swapin/IO wait percentages. Enable temporarily with `sudo sysctl -w kernel.task_delayacct=1`.

### `strace`

Install via `strace`:

```bash
# [ROOT] Install strace
sudo pacman -S --needed strace

# [ROOT] Trace file opens and network calls of a running PID and its children
sudo strace -f -e trace=file,network -p 1234

# [NON-ROOT] Summarize syscall latency and counts to find bottlenecks
strace -c -f curl -sS https://example.com >/dev/null
```

> **Watch out:** Attaching `strace` to a latency-sensitive production daemon (database, Envoy, nginx under heavy RPS) pauses the process on every syscall entry/exit and can degrade throughput by 10x–50x. Prefer `perf` or eBPF (`bpftrace`) on hot paths.

## Networking and Packet Inspection

### `ss` and `ip` (`iproute2`)

Preinstalled via `iproute2`:

```bash
# [ROOT] List all listening TCP/UDP sockets with owning PID and process name
sudo ss -tulnp

# [NON-ROOT] Show established TCP connections with congestion/RTT metrics
ss -tin state established

# [NON-ROOT] Colorized JSON-capable interface addresses and routing table
ip -br -c addr
ip -c route show table all
```

> **Watch out:** Without `sudo`, `ss -tulnp` omits the `users:(("proc",pid=...))` column for sockets owned by root or other system users.

### `tcpdump`

Install via `tcpdump`:

```bash
# [ROOT] Install tcpdump
sudo pacman -S --needed tcpdump

# [ROOT] Capture DNS queries across all interfaces without reverse-DNS lookups
sudo tcpdump -i any -nn port 53

# [ROOT] Write full-size packets to a rotating pcap file for Wireshark analysis
sudo tcpdump -i eth0 -s 0 -W 5 -C 50 -w /tmp/capture.pcap 'tcp port 443'
```

> **Watch out:** Omitting `-n` causes `tcpdump` to perform reverse DNS lookups for every captured IP, flooding your capture with extra port 53 packets and stalling output when DNS is degraded.

### `mtr`

Install via `mtr`:

```bash
# [ROOT] Install mtr
sudo pacman -S --needed mtr

# [NON-ROOT] Run a 50-packet non-interactive report with ASN and numeric IPs
mtr -rwzbc 50 1.1.1.1

# [ROOT] Probe using TCP SYN on port 443 when intermediate routers drop ICMP
sudo mtr -T -P 443 -rwbc 30 1.1.1.1
```

> **Watch out:** Packet loss at a single intermediate router hop that does NOT carry through to the final destination indicates ICMP rate-limiting on that router's control plane, not real forwarding loss.

### `bandwhich`

Install via `bandwhich`:

```bash
# [ROOT] Install bandwhich
sudo pacman -S --needed bandwhich

# [ROOT] Live terminal breakdown of bandwidth by process, remote IP, and socket
sudo bandwhich -i eth0

# [ROOT] Raw text output for logging without DNS resolution
sudo bandwhich --raw --no-resolve
```

> **Watch out:** `bandwhich` sniffs packets via `libpcap` and maps them to `/proc` sockets; on high-throughput 10GbE+ links it can drop packets and under-report throughput.

## Storage and Filesystem Tools

### `ncdu`

Install via `ncdu`:

```bash
# [ROOT] Install ncdu
sudo pacman -S --needed ncdu

# [ROOT] Scan root filesystem without crossing into /proc, /sys, or NFS mounts
sudo ncdu -x /

# [ROOT] Export scan on a headless server and inspect locally
sudo ncdu -x -o /tmp/disk.json / && ncdu -f /tmp/disk.json
```

> **Watch out:** Always pass `-x` when scanning `/`. Without `-x`, `ncdu` traverses virtual filesystems and mounted network shares, inflating totals and hanging on slow NFS/SMB mounts.

### `smartmontools`

Install via `smartmontools`:

```bash
# [ROOT] Install smartmontools
sudo pacman -S --needed smartmontools

# [ROOT] Full SMART health and wear-level report for NVMe or SATA
sudo smartctl -a /dev/nvme0n1

# [ROOT] Start a non-destructive background short self-test
sudo smartctl -t short /dev/sda
```

> **Watch out:** On RAID controllers (MegaRAID, HP SmartArray) or USB enclosures, `smartctl` requires explicit device type flags such as `-d sat` or `-d megaraid,0` or it will report unreadable attributes.

## Boot, Kernel, and Journald Forensics

### `journalctl` and `systemd-analyze`

Preinstalled via `systemd`:

```bash
# [NON-ROOT] Show errors and critical messages from the current boot
journalctl -b -p err..emerg

# [NON-ROOT] Inspect logs from the previous boot after an unexpected crash or kernel panic
journalctl -b -1 -e

# [NON-ROOT] Profile boot time per unit and critical dependency chain
systemd-analyze blame | head -n 20
systemd-analyze critical-chain
```

> **Watch out:** If `Storage=volatile` is set or `/var/log/journal` does not exist, `journalctl -b -1` returns no data after a reboot. Ensure persistent journaling by checking `/var/log/journal` exists and `Storage=auto` (or `persistent`) in `/etc/systemd/journald.conf`.

### `mkinitcpio`

Preinstalled via `mkinitcpio`:

```bash
# [ROOT] Rebuild all configured kernel presets
sudo mkinitcpio -P

# [ROOT] Rebuild a single preset with verbose module resolution
sudo mkinitcpio -p linux-lts -v

# [NON-ROOT] Inspect modules, hooks, and binaries embedded inside an initramfs image
lsinitcpio -a /boot/initramfs-linux.img
```

> **Watch out:** After editing `/etc/mkinitcpio.conf` (adding RAID, LVM, encryption, or filesystem modules), the changes do NOT take effect until `sudo mkinitcpio -P` completes cleanly without missing-module warnings.
