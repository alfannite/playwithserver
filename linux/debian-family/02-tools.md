# Debian, Ubuntu, and Proxmox VE Essential Tools

Production CLI reference for Debian-family package management, `nala`, `ufw`, `needrestart`, and AppArmor with exact install commands, real flags, and edge cases.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Package Management Reference](#package-management-reference)
- [Core APT and Package Utilities](#core-apt-and-package-utilities)
- [Networking and Firewall Tools](#networking-and-firewall-tools)
- [Service Restart and Patch Auditing](#service-restart-and-patch-auditing)
- [AppArmor Profile Management](#apparmor-profile-management)

## Package Management Reference

| Task | Command | Scope |
| :--- | :--- | :--- |
| Search package metadata | `apt-cache search <term>` | Remote/local repo cache |
| Show versions & repo priority | `apt-cache policy <pkg>` | Pinning & backports verification |
| Find which package owns an installed file | `dpkg -S /usr/sbin/ss` | Installed packages only |
| Find which repo package provides a missing file | `apt-file search bin/dig` | All configured repositories |
| List files installed by a package | `dpkg -L nginx-core` | Installed package inventory |
| Prevent a package from upgrading | `apt-mark hold <pkg>` | Kernel/DB version locking |
| Inspect manually installed packages | `apt-mark showmanual` | Reproducible host auditing |

## Core APT and Package Utilities

### apt, apt-cache, and apt-mark

Pre-installed on all Debian, Ubuntu, and Proxmox VE hosts (`apt` package).

```bash
# Inspect candidate version, installed version, and pin priorities [NON-ROOT]
apt-cache policy linux-image-amd64

# Install a package specifically from Debian backports [ROOT]
apt-get install -t "$(. /etc/os-release && echo "${VERSION_CODENAME}-backports")" wireguard-tools

# Hold critical database or kubelet packages during routine OS patching [ROOT]
apt-mark hold kubelet kubeadm kubectl
apt-mark showhold

# Dry-run an upgrade to see removals before touching the system [NON-ROOT]
apt-get -s full-upgrade
```

> **Watch out:** Never use interactive `apt` inside automation scripts or cron jobs; its CLI output is intentionally unstable and emits warnings. Always use `apt-get` or `apt-cache` with `DEBIAN_FRONTEND=noninteractive` in scripts.

### nala

Modern parallel-downloading frontend for `libapt-pkg` with formatted transaction tables, history rollback, and fastest-mirror selection.

Install:

`[ROOT]`
```bash
apt-get update && apt-get install -y nala
```

Usage:

```bash
# Update cache and upgrade with clean tabular diff output [ROOT]
nala upgrade

# Benchmark mirrors and save fastest low-latency sources [ROOT]
nala fetch --auto --https-only --country US

# Review past package transactions and roll back a broken install [ROOT]
nala history
nala history undo 14
```

> **Watch out:** Running `nala fetch` writes `/etc/apt/sources.list.d/nala-sources.list`, which can duplicate existing suites in `/etc/apt/sources.list` and cause duplicate target warnings. Avoid running `nala fetch` on Proxmox VE nodes so Proxmox repository priorities remain intact.

### dpkg and apt-file

`dpkg` is pre-installed; install `apt-file` to search uninstalled package contents:

`[ROOT]`
```bash
apt-get install -y apt-file && apt-file update
```

Usage:

```bash
# Locate which package owns a binary or config file on disk [NON-ROOT]
dpkg -S /etc/chrony/chrony.conf

# Search repositories for a missing header or shared library [NON-ROOT]
apt-file search libssl.so.3

# Repair an interrupted package installation after an SSH drop [ROOT]
dpkg --configure -a
apt-get install -f

# Purge residual config files left behind by removed packages ("rc" state) [ROOT]
dpkg -l | awk '/^rc/ {print $2}' | xargs -r dpkg --purge
```

> **Watch out:** Installing a local `.deb` via `dpkg -i file.deb` does not resolve missing dependencies and leaves the package in a broken state. Use `apt-get install ./file.deb` instead so APT resolves dependencies automatically.

## Networking and Firewall Tools

### ufw (Uncomplicated Firewall)

Install (pre-installed on Ubuntu Server; optional on Debian):

`[ROOT]`
```bash
apt-get install -y ufw
```

Usage:

```bash
# Set baseline defaults and allow SSH BEFORE enabling [ROOT]
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH management'

# Restrict PostgreSQL to a specific internal subnet [ROOT]
ufw allow from 10.10.20.0/24 to any port 5432 proto tcp comment 'App subnet to PG'

# Inspect numbered rules and delete by index [ROOT]
ufw status numbered
ufw delete 3
```

> **Watch out:** Docker modifies `iptables`/`nftables` directly and inserts `DOCKER-USER` and `PREROUTING` NAT rules **before** `ufw` input chains. A port published via `docker run -p 5432:5432` is publicly reachable even when `ufw default deny incoming` is active. Bind local-only containers to `127.0.0.1:5432:5432` or enforce ingress rules in the `DOCKER-USER` chain. Do not install `ufw` on Proxmox VE hosts; use the native Proxmox cluster firewall (`pve-firewall`) instead.

### ifupdown2 (Debian / Proxmox VE)

Pre-installed on Proxmox VE; optional replacement for legacy `ifupdown` on Debian:

`[ROOT]`
```bash
apt-get install -y ifupdown2
```

Usage:

```bash
# Dry-run syntax and dependency validation before applying [ROOT]
ifreload -a -n

# Apply /etc/network/interfaces changes live without dropping active SSH sessions [ROOT]
ifreload -a

# Inspect parsed interface dependency graph [ROOT]
ifquery -a --running
```

> **Watch out:** Installing `ifupdown2` removes legacy `ifupdown`. Validate that no custom hooks in `/etc/network/if-up.d/` rely on legacy `ifupdown` environment quirks before converting a remote Debian host.

## Service Restart and Patch Auditing

### needrestart

Detects running daemons holding deleted shared libraries after security updates and checks whether a newer kernel is waiting for a reboot.

Install:

`[ROOT]`
```bash
apt-get install -y needrestart
```

Usage:

```bash
# Audit outdated daemons, kernel status, and microcode in batch mode (no restarts) [ROOT]
needrestart -b

# List only services requiring restart with human-readable output [ROOT]
needrestart -r l

# Automatically restart affected services non-interactively [ROOT]
needrestart -r a
```

> **Watch out:** On Ubuntu 22.04+, `needrestart` triggers interactive TUI prompts during `apt upgrade`, which can hang automation or unexpectedly restart container engines/databases when set to automatic mode. Configure exclusions in `/etc/needrestart/conf.d/` for critical stateful services.

## AppArmor Profile Management

### apparmor-utils

Install (AppArmor kernel module is enabled by default on Debian 12+ and Ubuntu):

`[ROOT]`
```bash
apt-get install -y apparmor-utils apparmor-profiles
```

Usage:

```bash
# Display loaded profiles in enforce vs. complain mode and unconfined processes [ROOT]
aa-status

# Switch a misbehaving profile to complain mode (logs denials without blocking) [ROOT]
aa-complain /usr/sbin/named

# Interactively generate allow rules from recent audit/journal denials [ROOT]
aa-logprof

# Return profile to enforce mode once updated [ROOT]
aa-enforce /usr/sbin/named
```

> **Watch out:** Never disable the entire `apparmor.service` to work around a single application denial. Use `aa-complain` on the specific binary profile, capture the missing paths with `aa-logprof`, and add local rules under `/etc/apparmor.d/local/<profile>` so package upgrades preserve your customization.
