# Termux Pocket Linux Toolbelt

Categorized tool matrix, exact `pkg` installation commands, production flags, and real-world edge cases for running services inside Termux.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Tool Matrix](#tool-matrix)
- [pkg and termux-change-repo](#pkg-and-termux-change-repo)
- [openssh](#openssh)
- [termux-services](#termux-services)
- [proot-distro](#proot-distro)
- [cloudflared](#cloudflared)
- [termux-api](#termux-api)
- [tmux](#tmux)

## Tool Matrix

| Tool | Termux Package | Primary Use Case | Privileges Required |
| --- | --- | --- | --- |
| `pkg` | Built-in (`termux-tools`) | Wrapper around `apt`/`dpkg` with mirror failover | `[NON-ROOT]` |
| `sshd` | `openssh` | Remote shell & SFTP server on TCP port 8022 | `[NON-ROOT]` |
| `sv` / `sv-enable` | `termux-services` | `runit`-based daemon supervision and log rotation | `[NON-ROOT]` |
| `proot-distro` | `proot-distro` | Userspace Debian, Alpine, and Ubuntu rootfs containers | `[NON-ROOT]` |
| `cloudflared` | `cloudflared` | Outbound Zero-Trust tunnels exposing HTTP/SSH behind CGNAT | `[NON-ROOT]` |
| `termux-wake-lock` / `termux-battery-status` | `termux-api` (+ F-Droid APK) | Hardware wake locks, battery/thermal JSON telemetry, Wi-Fi queries | `[NON-ROOT]` |
| `tmux` | `tmux` | Persistent terminal multiplexing across dropped SSH links | `[NON-ROOT]` |

## pkg and termux-change-repo

Termux package manager frontend that handles mirror selection and wraps `apt` safely for Android's non-FHS `$PREFIX` (`/data/data/com.termux/files/usr`).

### Install

Preinstalled in every F-Droid Termux build.

### Real-World Usage

`[NON-ROOT]`

```bash
# Switch to a faster mirror group when default mirror throttles or returns 503
termux-change-repo

# Search, inspect metadata, and install packages cleanly
pkg search cloudflared
pkg show openssh
pkg install -y ripgrep fd bat

# List all explicitly installed packages and reclaim cached .deb space
pkg list-installed
apt autoremove -y && apt clean
```

> **Watch out:** Never run `pkg` or `apt` as `root` (e.g., inside `tsu` / `su`) on standard Termux files. Doing so changes ownership of `$PREFIX/var/lib/dpkg` and `$PREFIX/var/cache/apt` to `uid=0`, breaking all subsequent non-root `pkg` commands with `Permission denied`.

## openssh

OpenSSH client and daemon patched for Termux's unprivileged single-UID model and `$PREFIX` directory layout.

### Install

`[NON-ROOT]`

```bash
pkg install -y openssh
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Validate sshd_config syntax before reloading
sshd -t

# Run sshd in foreground with debug logging on an alternate port for live auth troubleshooting
sshd -D -d -p 8023

# Start background daemon normally (listens on 8022 per $PREFIX/etc/ssh/sshd_config)
sshd

# Inspect active SSH connections using modern ss
ss -tnp state established '( sport = :8022 )'
```

> **Watch out:** Termux `sshd` does not use `/etc/passwd` or Linux PAM; every SSH login executes as the single Android app UID assigned to `com.termux` (such as `u0_a241`). Any username passed by the client (`ssh foo@ip -p 8022`) is accepted if the key matches `~/.ssh/authorized_keys`.

## termux-services

Provides `runit` (`runsvdir`, `runsv`, `sv`, `svlogd`) preconfigured for Termux so daemons restart automatically on crash and write rotated logs under `$PREFIX/var/log/sv/`.

### Install

`[NON-ROOT]`

```bash
pkg install -y termux-services
# Close and reopen Termux (or start runsvdir manually) after installation
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Enable a service to start automatically with runsvdir (creates symlink in $PREFIX/var/service/)
sv-enable sshd
sv-enable crond

# Inspect running state, PID, uptime, and log daemon status
sv status sshd

# Control lifecycle: start, graceful restart, stop, or disable autostart
sv up sshd
sv restart sshd
sv down sshd
sv-disable sshd
```

> **Watch out:** Immediately after `pkg install termux-services`, running `sv status sshd` fails with `warning: sshd: unable to open supervise/ok: file does not exist` until you completely close and relaunch the Termux session (so `runsvdir` spawns) or launch `runsvdir -P "$PREFIX/var/service" &` manually.

## proot-distro

Manages full Linux userspace distributions (Debian, Alpine, Ubuntu, Arch, Fedora) inside Termux via `proot` (`ptrace`-based path translation), requiring zero root privileges.

### Install

`[NON-ROOT]`

```bash
pkg install -y proot-distro
```

### Real-World Usage

`[NON-ROOT]`

```bash
# List available upstream rootfs images and install Debian or Alpine
proot-distro list
proot-distro install debian
proot-distro install alpine

# Enter Debian with Android shared storage bind-mounted and Termux /tmp accessible
proot-distro login debian --shared-tmp --bind /sdcard/ServerData:/srv/data

# Execute a single non-interactive command inside the guest distribution
proot-distro login alpine -- apk update && proot-distro login alpine -- apk add python3

# Create a portable compressed snapshot of the entire guest rootfs
proot-distro backup debian --output ~/storage/downloads/debian-backup.tar.gz
```

> **Watch out:** `proot` intercepts every filesystem syscall via `ptrace`, adding measurable CPU overhead on metadata-heavy workloads (`npm install`, large `git status`, compiling C++). Keep I/O-heavy services native to Termux packages whenever a native Termux package exists, and reserve `proot-distro` for glibc-only binaries or distribution-specific toolchains.

## cloudflared

Cloudflare Tunnel daemon that creates outbound-only QUIC/HTTP2 connections from your phone to Cloudflare's edge, exposing local web apps or SSH servers without port forwarding, static IPs, or public IPv4 addresses.

### Install

`[NON-ROOT]`

```bash
pkg install -y cloudflared
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Ephemeral test tunnel exposing a local HTTP service on port 8080 (no Cloudflare account required)
cloudflared tunnel --url http://127.0.0.1:8080

# Authenticate to your Cloudflare account and create a persistent named tunnel
cloudflared tunnel login
cloudflared tunnel create pocket-node-01

# Route a DNS hostname to the named tunnel
cloudflared tunnel route dns pocket-node-01 node01.example.com

# Run tunnel with explicit ingress config (use --protocol http2 if mobile CGNAT drops UDP/QUIC)
cloudflared tunnel --config ~/.cloudflared/config.yml --protocol http2 run pocket-node-01
```

> **Watch out:** Many cellular carriers and strict Wi-Fi firewalls throttle or drop long-lived UDP flows, causing `cloudflared` QUIC tunnels to flap with `failed to dial to edge with quic`. Pass `--protocol http2` in your `runit` service script for stable 24/7 operation on mobile networks.

## termux-api

Command-line bridge to Android OS APIs via the companion `Termux:API` F-Droid app.

### Install

Install the **Termux:API** APK from F-Droid first, then install the CLI package in Termux:

`[NON-ROOT]`

```bash
pkg install -y termux-api
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Acquire and release partial CPU wake-lock (prevents CPU sleep while screen is off)
termux-wake-lock
termux-wake-unlock

# Query battery percentage, voltage, temperature (Celsius), and plugged state as JSON
termux-battery-status | jq '{percentage, status, plugged, temperature}'

# Query current Wi-Fi SSID, IP, link speed, and RSSI signal strength
termux-wifi-connectioninfo | jq '{ssid, ip, rssi, link_speed_mbps}'

# Send a persistent local Android notification from a cron/watchdog alert script
termux-notification --id health-alert --title "Node Alert" --content "Battery temp exceeded 42C"
```

> **Watch out:** Running any `termux-*` API command when the **Termux:API** F-Droid app is missing, outdated, or force-stopped causes the CLI command to hang indefinitely waiting on an Android broadcast reply. Always wrap `termux-battery-status` and `termux-wifi-connectioninfo` in `timeout 5` inside automated monitoring scripts.

## tmux

Terminal multiplexer for keeping interactive builds, tails, and ad-hoc servers alive if Wi-Fi or SSH disconnects.

### Install

`[NON-ROOT]`

```bash
pkg install -y tmux
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Start or attach to a named admin session
tmux new-session -A -s ops

# List active sessions and kill a stale one
tmux ls
tmux kill-session -t stale-build

# Run a detached background task and inspect its scrollback later
tmux new-session -d -s sync 'rsync -avh --progress ~/data/ user@backup:/srv/phone/'
```

> **Watch out:** Do not confuse `tmux` with a proper daemon supervisor. Use `tmux` for interactive sessions, and use `termux-services` (`runit`) for production daemons that must auto-restart after crashes and launch automatically via `Termux:Boot`.
