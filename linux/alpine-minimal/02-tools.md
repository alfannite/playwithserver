# Alpine Linux Essential Tools

Categorized production, OpenRC, `apk`, `lbu`, and diagnostic toolchain for Alpine Linux hosts and containers with exact `apk add` commands, real-world flags, and BusyBox/`musl` edge cases.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Tooling Matrix](#tooling-matrix)
- [Package, Service, and Diskless Management](#package-service-and-diskless-management)
- [Networking and Firewall Tools](#networking-and-firewall-tools)
- [Performance and Process Diagnostics](#performance-and-process-diagnostics)
- [Storage, Hardware, and Logging Tools](#storage-hardware-and-logging-tools)

## Tooling Matrix

| Category | Tool | `apk` Package | Primary Purpose |
| :--- | :--- | :--- | :--- |
| Package | `apk` | `apk-tools` (preinstalled) | Package install, world management, integrity audit |
| Service | `rc-service` / `rc-update` / `rc-status` | `openrc` (preinstalled) | OpenRC daemon control and runlevel configuration |
| Diskless | `lbu` | `alpine-conf` (preinstalled) | RAM-root overlay diffing and persistent commits |
| Privilege | `doas` | `doas` | Minimal privilege escalation replacing `sudo` |
| Network | `ss` / `ip` | `iproute2` / `iproute2-ss` | Modern socket inspection and routing/interface control |
| Network | `tcpdump` | `tcpdump` | Packet capture and BPF filtering |
| Network | `drill` / `dig` | `ldns-tools` / `bind-tools` | DNS query and DNSSEC diagnostics |
| Network | `mtr` | `mtr` | Continuous path latency and loss diagnostics |
| Firewall | `nft` / `awall` | `nftables` / `awall` | Native netfilter firewall and JSON policy compiler |
| Performance | `btop` / `htop` | `btop` / `htop` | Interactive CPU, memory, disk, and network monitor |
| Performance | `iostat` / `pidstat` | `sysstat` | Disk I/O latency and per-PID telemetry |
| Performance | `strace` | `strace` | Syscall tracing and `musl` runtime debugging |
| Storage | `ncdu` | `ncdu` | Disk usage analyzer |
| Storage | `smartctl` | `smartmontools` | NVMe/SATA SMART diagnostics |
| Storage | `lsblk` / `findmnt` | `lsblk` / `findmnt` (`util-linux`) | Block device topology and mount tree |

## Package, Service, and Diskless Management

### `apk`

Preinstalled via `apk-tools`:

```sh
# [ROOT] Install packages without writing local index cache (mandatory in Dockerfiles)
apk add --no-cache curl ca-certificates jq

# [ROOT] Group temporary build dependencies under a virtual package and purge cleanly
apk add --no-cache --virtual .build-deps build-base linux-headers && \
  # ... compile step ...
  apk del .build-deps

# [NON-ROOT] Find which package owns a file
apk info --who-owns /usr/sbin/sshd

# [ROOT] Audit filesystem against APK database for added, modified, or missing files
apk audit --backup

# [ROOT] Reinstall corrupted or missing files for a specific package
apk fix --reinstall openssh-server
```

> **Watch out:** Running `apk update` without `--no-cache` leaves `/var/cache/apk/APKINDEX.*.tar.gz` inside container layers, bloating minimal images by several megabytes. Always use `apk add --no-cache` in `Dockerfile` builds.

### OpenRC (`rc-service`, `rc-update`, `rc-status`)

Preinstalled via `openrc`:

```sh
# [NON-ROOT] Show all services across all runlevels and their current state
rc-status --all

# [NON-ROOT] Show only crashed services (PID exited unexpectedly while marked started)
rc-status --crashed

# [ROOT] Start, restart, or reload a service
rc-service nginx restart
rc-service sshd reload

# [ROOT] Enable a service at boot (default runlevel) or remove it
rc-update add chronyd default
rc-update del chronyd default
```

> **Watch out:** OpenRC tracks daemon state via files under `/run/openrc/started/`. If a daemon dies abnormally, `rc-status` marks it `crashed` and refuses `rc-service <svc> start` until you run `rc-service <svc> zap` (or `restart`).

### `lbu` (Alpine Local Backup)

Preinstalled via `alpine-conf` (for `diskless` and `data` installs):

```sh
# [ROOT] Show modified or untracked config files since last commit
lbu status -a

# [ROOT] Inspect exact unified diff before committing to flash/disk
lbu diff

# [ROOT] Add a custom directory or file outside /etc to the overlay archive
lbu include /usr/local/bin/custom-script.sh

# [ROOT] Save current configuration overlay to backup media
lbu commit -d
```

> **Watch out:** `lbu` only backs up `/etc` and `/etc/apk/world` by default. Files written to `/root`, `/home`, or `/opt` disappear on reboot in diskless mode unless explicitly registered with `lbu include`.

### `doas`

Install via `doas`:

```sh
# [ROOT] Install doas
apk add doas

# [NON-ROOT] Run a single administrative command as root
doas rc-service nftables reload

# [NON-ROOT] Spawn an interactive root shell
doas -s

# [ROOT] Validate syntax of a doas configuration file before applying
doas -C /etc/doas.d/20-wheel.conf
```

> **Watch out:** Unlike `sudo`, `doas` has no `-i` flag, resets `PATH` to a strict safe default unless `keepenv` or `setenv` is specified, and does not read `/etc/sudoers`.

## Networking and Firewall Tools

### `ip` and `ss` (`iproute2`)

Install via `iproute2` and `iproute2-ss` (BusyBox's built-in `ip` lacks JSON, `-br`, and advanced routing flags, and BusyBox has no `ss`):

```sh
# [ROOT] Install full iproute2 and ss
apk add iproute2 iproute2-ss

# [ROOT] List all listening TCP/UDP sockets with owning process
doas ss -tulnp

# [NON-ROOT] Compact colorized link/address summary and policy routing rules
ip -br -c addr
ip -c route show table all
```

> **Watch out:** Installing only `iproute2` on newer Alpine versions installs meta-dependencies, whereas `iproute2-ss` provides the standalone `ss` binary without pulling full `tc`/`bridge` utilities in tiny containers.

### `tcpdump`

Install via `tcpdump`:

```sh
# [ROOT] Install tcpdump
apk add tcpdump

# [ROOT] Capture DNS and DHCP traffic with numeric IPs and ports
doas tcpdump -i any -nn 'port 53 or port 67 or port 68'

# [ROOT] Capture HTTP/TLS handshake packets on eth0 to a pcap file
doas tcpdump -i eth0 -s 0 -w /tmp/edge.pcap 'tcp port 443'
```

> **Watch out:** Always pass `-nn` on minimal Alpine nodes with restricted DNS or no `/etc/services` lookups; otherwise `tcpdump` stalls attempting reverse resolution.

### `drill` (`ldns-tools`) or `dig` (`bind-tools`)

`drill` is much lighter than `bind-tools` for containers and edge routers:

```sh
# [ROOT] Install lightweight DNS tool drill (or bind-tools for dig)
apk add ldns-tools

# [NON-ROOT] Query A/AAAA records directly against a specific resolver
drill @1.1.1.1 AAAA alpinelinux.org

# [NON-ROOT] Trace full DNS delegation path from root servers
drill -T example.com
```

> **Watch out:** `drill` and `dig` query DNS servers directly and bypass `musl`'s `getaddrinfo()` resolver logic. To reproduce application-level `musl` DNS behavior (like search domains or `ndots`), test with `getent ahosts <name>`.

### `awall` (Alpine Wall)

Install via `awall` (compiles clean JSON policies into `iptables`/`nftables` rules with built-in lockout protection):

```sh
# [ROOT] Install awall and nftables backend
apk add awall nftables

# [ROOT] List available and enabled policy files
doas awall list

# [ROOT] Activate policy with a 10-second confirmation prompt (auto-rolls back if SSH drops)
doas awall activate
```

> **Watch out:** Running `awall activate -f` skips the interactive rollback prompt. On remote routers or cloud VMs, never use `-f` on a newly edited policy until `awall translate` has been verified.

## Performance and Process Diagnostics

### `btop` and `htop`

Install via `btop` (or `htop` for tiny memory footprint):

```sh
# [ROOT] Install btop
apk add btop

# [NON-ROOT] Start btop in low-overhead TTY mode over serial/SSH console
btop --tty_on

# [NON-ROOT] Start htop filtered to a specific user
htop -u nginx
```

> **Watch out:** BusyBox's built-in `top` and `ps` do not accept GNU flags like `ps auxf` or `ps -ef --forest`. Install `procps-ng` if monitoring scripts depend on full GNU `ps` flags.

### `sysstat` (`iostat`, `pidstat`, `mpstat`)

Install via `sysstat`:

```sh
# [ROOT] Install sysstat
apk add sysstat

# [NON-ROOT] Extended block device latency and queue saturation every 2s
iostat -xz 2

# [NON-ROOT] Per-PID CPU, memory, and disk I/O every 2s
pidstat -urd 2
```

> **Watch out:** Always ignore the first output frame from `iostat` and `mpstat`—it shows averages since boot, not real-time samples.

### `strace`

Install via `strace`:

```sh
# [ROOT] Install strace
apk add strace

# [ROOT] Trace DNS config reads, file opens, and network connects of a failing binary
strace -f -e trace=openat,connect,sendto,recvfrom /usr/local/bin/app

# [ROOT] Attach to a running daemon PID and count syscall time
doas strace -c -p 412
```

> **Watch out:** Inside Docker/OCI containers, `strace` requires `CAP_SYS_PTRACE` (`--cap-add=SYS_PTRACE`) and a seccomp profile that permits `ptrace`.

## Storage, Hardware, and Logging Tools

### `ncdu`

Install via `ncdu`:

```sh
# [ROOT] Install ncdu
apk add ncdu

# [ROOT] Inspect root filesystem usage without crossing mount points
doas ncdu -x /
```

> **Watch out:** On diskless hosts where `/` is `tmpfs`, scanning `/` without `-x` mixes RAM usage with mounted persistent disks (`/media/sda1` or `/var`).

### `smartmontools`

Install via `smartmontools`:

```sh
# [ROOT] Install smartmontools
apk add smartmontools

# [ROOT] Inspect NVMe/SATA health and error logs
doas smartctl -a /dev/nvme0n1

# [ROOT] Trigger a short background self-test
doas smartctl -t short /dev/sda
```

> **Watch out:** Enable `smartd` via `rc-update add smartd default` if you want background SMART failure alerts written to syslog.

### `util-linux` (`lsblk`, `findmnt`)

Install via `lsblk` and `findmnt` (Alpine splits `util-linux` into granular subpackages):

```sh
# [ROOT] Install lsblk and findmnt individually to keep footprint small
apk add lsblk findmnt

# [NON-ROOT] Inspect block devices, UUIDs, filesystems, and mountpoints
lsblk -f

# [NON-ROOT] Display mount hierarchy and active mount options
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
```

> **Watch out:** Installing the umbrella `util-linux` package pulls many utilities you may not need in a container; Alpine lets you install just `lsblk`, `findmnt`, `flock`, or `blkid` individually.
