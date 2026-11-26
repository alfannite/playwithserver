# openSUSE Family Essential Tools

Categorized production and diagnostic toolchain for openSUSE Leap, Tumbleweed, and MicroOS covering `zypper`, `snapper`, `transactional-update`, YaST CLI, `firewalld`, SELinux/AppArmor, and performance tools.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Tooling Matrix](#tooling-matrix)
- [SUSE Package, Snapshot, and Immutable OS Tools](#suse-package-snapshot-and-immutable-os-tools)
- [Networking and Firewall Tools](#networking-and-firewall-tools)
- [Performance and Process Diagnostics](#performance-and-process-diagnostics)
- [Storage, Btrfs, and Security Inspection](#storage-btrfs-and-security-inspection)

## Tooling Matrix

| Category | Tool | Package (`zypper`) | Primary Purpose |
| :--- | :--- | :--- | :--- |
| Package | `zypper` | `zypper` (preinstalled) | RPM solver, repo control, locks, deleted-lib detection |
| Snapshot | `snapper` | `snapper` (preinstalled) | Btrfs snapshot creation, diffing, and rollback |
| Immutable | `transactional-update` / `rebootmgrctl` | `transactional-update` / `rebootmgr` (MicroOS) | Atomic read-only root updates and reboot scheduling |
| Admin TUI | `yast2` / `yast` | `yast2` (Leap/Tumbleweed) | Modular ncurses and CLI system configuration |
| Network | `ss` / `ip` | `iproute2` (preinstalled) | Socket inspection, interfaces, and policy routing |
| Network | `nmcli` / `wicked` | `NetworkManager` / `wicked` | Network interface configuration |
| Network | `tcpdump` / `mtr` | `tcpdump` / `mtr` | Packet capture and path loss diagnostics |
| Firewall | `firewall-cmd` | `firewalld` (preinstalled) | Zone-based firewall (`nftables` backend) |
| Performance | `btop` / `sysstat` | `btop` / `sysstat` | Live resource monitor and `iostat`/`pidstat` |
| Performance | `strace` | `strace` | Syscall tracing |
| Storage | `btrfs` / `ncdu` / `smartctl` | `btrfsprogs` / `ncdu` / `smartmontools` | Btrfs subvolumes, disk usage, SMART telemetry |
| Security | `semanage` / `aa-status` | `policycoreutils-python-utils` / `apparmor-utils` | SELinux (TW/MicroOS) and AppArmor (Leap) control |

## SUSE Package, Snapshot, and Immutable OS Tools

### `zypper`

Preinstalled across openSUSE variants:

```bash
# [ROOT] List processes holding deleted shared libraries after an upgrade (shows which services need restart)
sudo zypper ps -s

# [ROOT] Search which package provides a specific binary, library, or capability
zypper search --provides /usr/bin/dig
zypper wp 'libssl.so.3()(64bit)'

# [ROOT] Lock a package version to prevent unintended upgrades and list active locks
sudo zypper addlock 'kernel-default'
zypper locks
sudo zypper removelock 1

# [ROOT] Dry-run an upgrade without downloading or modifying the system
sudo zypper dup --dry-run
```

> **Watch out:** Leaving a kernel or core library locked via `zypper addlock` blocks security patches and causes dependency solver conflicts on Tumbleweed. Audit `zypper locks` before every major maintenance cycle.

### `snapper`

Preinstalled on Btrfs installs (`snapper`, `snapper-zypp-plugin`):

```bash
# [ROOT] List all snapshots with pre/post pairs, timestamps, and descriptions
sudo snapper list

# [ROOT] Show list of files added, modified, or removed between two snapshots
sudo snapper status 42..45

# [ROOT] Print unified file diff between snapshot 42 and 45 for a specific config
sudo snapper diff 42..45 /etc/ssh/sshd_config

# [ROOT] Take a manual named snapshot before a risky change
sudo snapper create --description "before-nginx-refactor"
```

> **Watch out:** `snapper` does NOT snapshot `/var`, `/tmp`, `/srv`, or `/home` because openSUSE isolates them as separate Btrfs subvolumes so rolling back the OS never wipes databases, logs, or user data. Back up `/var/lib/postgresql` or `/srv` independently.

### `transactional-update` and `rebootmgrctl` (MicroOS)

Preinstalled on openSUSE MicroOS:

```bash
# [ROOT] Install a package into a new snapshot without touching the live root
sudo transactional-update pkg in --no-recommends wireguard-tools

# [ROOT] Open an interactive chroot shell inside a new snapshot to edit /usr or run custom commands
sudo transactional-update shell

# [ROOT] Revert to the previous working snapshot if a staged or booted update is broken
sudo transactional-update rollback

# [ROOT] Trigger an immediate reboot respecting rebootmgr locks, or inspect schedule
sudo rebootmgrctl status
```

> **Watch out:** Running two separate `transactional-update` commands without rebooting between them creates independent snapshots branched from the **currently running** snapshot, discarding the first command's changes unless you pass `--continue` (`sudo transactional-update --continue pkg in ...`).

### YaST CLI (`yast2` / `yast`)

Preinstalled on Leap and Tumbleweed (not used on MicroOS):

```bash
# [ROOT] Install core YaST CLI modules if minimal install omitted them
sudo zypper in --no-recommends yast2 yast2-network yast2-firewall yast2-bootloader

# [ROOT] Launch interactive ncurses TUI over SSH (works cleanly without X11/Wayland)
sudo yast2

# [ROOT] Open a specific module directly (network, bootloader, services-manager)
sudo yast2 lan
sudo yast2 bootloader

# [ROOT] Run non-interactive CLI subcommands
sudo yast services-manager list
```

> **Watch out:** Editing `/etc/sysconfig/network/ifcfg-*` by hand while `yast2 lan` is open overwrites your manual edits when YaST writes out its configuration.

## Networking and Firewall Tools

### `ss` and `ip` (`iproute2`)

Preinstalled via `iproute2`:

```bash
# [ROOT] Show all listening sockets and owning processes
sudo ss -tulnp

# [NON-ROOT] Show established sockets with TCP timer and RTT metrics
ss -tin state established

# [NON-ROOT] Brief colorized interface and routing view
ip -br -c addr
ip -c route show table all
```

> **Watch out:** In `ss -tulnp`, wildcard IPv6 listeners (`[::]:22` with `IPV6_V6ONLY=0`) also accept IPv4 connections unless explicitly bound to `0.0.0.0` or `::` separately.

### `firewall-cmd` (`firewalld`)

Preinstalled via `firewalld`:

```bash
# [ROOT] Inspect active zones, interfaces, and allowed ports/services
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all

# [ROOT] Permanently allow HTTPS and reload cleanly
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# [ROOT] Temporarily allow a diagnostic port for 5 minutes (auto-expires)
sudo firewall-cmd --add-port=8080/tcp --timeout=300
```

> **Watch out:** Running `firewall-cmd --add-service=...` without `--permanent` applies only to runtime and disappears on reload or reboot. Conversely, `--permanent` does NOT take effect until `firewall-cmd --reload`.

### `tcpdump` and `mtr`

Install via `zypper in --no-recommends tcpdump mtr`:

```bash
# [ROOT] Capture HTTP/HTTPS SYN packets without DNS lookups
sudo tcpdump -i any -nn 'tcp[tcpflags] & tcp-syn != 0 and (port 80 or port 443)'

# [NON-ROOT] Non-interactive 50-packet path latency and loss report with ASNs
mtr -rwzbc 50 1.1.1.1
```

> **Watch out:** On systems running `firewalld` with `nftables`, `tcpdump` sees incoming packets **before** `firewalld` drops them. Seeing a packet in `tcpdump` confirms it arrived on the NIC, not that the firewall allowed it.

## Performance and Process Diagnostics

### `btop` and `sysstat`

Install via `zypper in --no-recommends btop sysstat`:

```bash
# [NON-ROOT] Start btop in TTY-safe ASCII mode over SSH
btop --tty_on

# [NON-ROOT] Block device latency and queue saturation every 2s
iostat -xz 2

# [NON-ROOT] Per-process CPU, I/O, and page faults every 2s
pidstat -urd 2
```

> **Watch out:** Enable `sysstat.service` (`sudo systemctl enable --now sysstat`) if you want historical `sar` metrics logged every 10 minutes for post-incident reviews.

### `strace`

Install via `zypper in --no-recommends strace`:

```bash
# [ROOT] Trace file access and permission errors (useful alongside SELinux/AppArmor debugging)
sudo strace -f -e trace=file -p 1842

# [NON-ROOT] Summarize syscall time distribution
strace -c -f /usr/sbin/nginx -t
```

> **Watch out:** Under SELinux enforcing mode on Tumbleweed/MicroOS, `strace` shows `EACCES` on files that appear `0644` in `ls -l`; check `ls -Z` and `ausearch -m avc` when `strace` reveals unexplained permission denials.

## Storage, Btrfs, and Security Inspection

### `btrfs` (`btrfsprogs`)

Preinstalled on Btrfs installs:

```bash
# [ROOT] Inspect true Btrfs data/metadata allocation (more accurate than df)
sudo btrfs filesystem usage -T /

# [ROOT] List all subvolumes and verify which snapshot is set as default boot target
sudo btrfs subvolume get-default /
sudo btrfs subvolume list /

# [ROOT] Check scrub status for silent data corruption
sudo btrfs scrub status /
```

> **Watch out:** Standard `df -h` can misreport free space on Btrfs when metadata chunks are exhausted or unallocated space is fragmented. Always inspect `btrfs filesystem usage /` before diagnosing `ENOSPC`.

### `semanage` / `ausearch` (Tumbleweed & MicroOS) and `aa-status` (Leap)

```bash
# [ROOT] Install SELinux policy CLI tools (Tumbleweed / MicroOS)
sudo zypper in --no-recommends policycoreutils-python-utils audit

# Inspect SELinux mode and recent AVC denials
sestatus
sudo ausearch -m avc,user_avc -ts recent

# [ROOT] Inspect AppArmor enforced/complain profiles (Leap)
sudo aa-status
```

> **Watch out:** Never permanently set `SELINUX=disabled` to fix a service denial—re-enabling it later requires a full filesystem relabel (`fixfiles -F onboot`) and reboot. Use `semanage` or `restorecon` to fix the label cleanly.
