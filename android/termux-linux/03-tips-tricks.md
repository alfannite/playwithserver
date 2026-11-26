# Termux Pocket Linux Tips & Tricks

Custom `runit` services, `proot-distro` vs `chroot` architecture trade-offs, CGNAT-proof SSH over `cloudflared`, and resilient headless operation tricks.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Create Custom runit Services Under termux-services](#create-custom-runit-services-under-termux-services)
- [Expose SSH and HTTP Behind CGNAT via cloudflared](#expose-ssh-and-http-behind-cgnat-via-cloudflared)
- [Termux Native vs proot-distro vs Rooted chroot](#termux-native-vs-proot-distro-vs-rooted-chroot)
- [Optimize proot-distro Storage and Bind Mounts](#optimize-proot-distro-storage-and-bind-mounts)
- [Fix Hardcoded Shebangs Automatically](#fix-hardcoded-shebangs-automatically)
- [Battery Temperature Watchdog via Cron](#battery-temperature-watchdog-via-cron)

## Create Custom runit Services Under termux-services

Any foreground process (Caddy, Gitea, Syncthing, `cloudflared`, Python API) can be turned into a self-healing `runit` service with automatic log rotation.

### Example: Supervised `cloudflared` Service with `svlogd`

`[NON-ROOT]` (Termux shell)

```bash
SVC_DIR="$PREFIX/var/service/cloudflared"
mkdir -p "$SVC_DIR/log"

cat > "$SVC_DIR/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
exec cloudflared tunnel \
  --no-autoupdate \
  --protocol http2 \
  --config "$HOME/.cloudflared/config.yml" \
  run pocket-node-01
EOF

cat > "$SVC_DIR/log/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
LOG_DIR="$PREFIX/var/log/sv/cloudflared"
mkdir -p "$LOG_DIR"
exec svlogd -tt "$LOG_DIR"
EOF

chmod 700 "$SVC_DIR/run" "$SVC_DIR/log/run"

# Enable and verify
sv-enable cloudflared
sv status cloudflared
tail -f "$PREFIX/var/log/sv/cloudflared/current"
```

Because `runit` expects foreground processes (`exec`), never append `&` or daemonize flags (`-d`) inside a `run` script; otherwise `runsv` assumes the service exited and spawns an infinite restart loop.

## Expose SSH and HTTP Behind CGNAT via cloudflared

Cellular networks and residential ISPs frequently place Android devices behind Carrier-Grade NAT (CGNAT) with no inbound port forwarding. A single `cloudflared` tunnel can multiplex both HTTPS web services and SSH (`port 8022`).

### 1. Configure Ingress Rules on the Android Node

`[NON-ROOT]` (Termux shell)

```bash
cat > ~/.cloudflared/config.yml <<'EOF'
tunnel: <YOUR-TUNNEL-UUID>
credentials-file: /data/data/com.termux/files/home/.cloudflared/<YOUR-TUNNEL-UUID>.json

ingress:
  - hostname: ssh-node01.example.com
    service: ssh://127.0.0.1:8022
  - hostname: app-node01.example.com
    service: http://127.0.0.1:8080
  - service: http_status:404
EOF
```

### 2. Connect from Your Workstation Using `ProxyCommand`

On your client workstation (`[NON-ROOT]`, requires `cloudflared` installed on the client):

```sshconfig
# Append to ~/.ssh/config
Host pocket-node-01
    HostName ssh-node01.example.com
    User termux
    IdentityFile ~/.ssh/id_ed25519_termux
    ProxyCommand cloudflared access ssh --hostname %h
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Then connect from anywhere in the world:

```bash
ssh pocket-node-01
```

## Termux Native vs proot-distro vs Rooted chroot

Choose the right runtime layer before deploying workloads so you do not fight kernel or Android sandbox constraints.

| Capability | Native Termux (`pkg`) | `proot-distro` (Non-Root) | Rooted `chroot` / Linux Deploy |
| --- | --- | --- | --- |
| Root Required | No | No | Yes (`[ROOT]`) |
| C Library | Android Bionic | Standard `glibc` (Debian/Ubuntu) or `musl` (Alpine) | Standard `glibc` / `musl` |
| Syscall Performance | Native speed (zero emulation overhead) | 10%–40% overhead on syscall-heavy I/O (`ptrace`) | Native speed |
| Bind Ports `< 1024` | No (use `>= 1024`, e.g., `8022`, `8080`) | No (fake UID 0 only; kernel still enforces app UID) | Yes (real kernel UID 0) |
| Run `systemd` / `dockerd` | No | No (no real cgroups/namespaces/mount privileges) | `dockerd` only with custom kernel enabling namespaces/cgroups |
| Best Workload Fit | `sshd`, `caddy`, `syncthing`, `cloudflared`, Python/Go/Rust binaries | `glibc`-only binaries, Debian/Alpine toolchains, `ansible`, `nginx` configs | Low-level netfilter tools, raw sockets, native-speed glibc servers |

> **Watch out:** Inside `proot-distro`, `whoami` prints `root` and `id` prints `uid=0`, which tricks install scripts into trying privileged kernel actions (`mount`, `setcap`, `iptables`, `chown` on Android `/sdcard`, or binding port 80). That UID 0 is strictly emulated by `proot`—the Android kernel still treats the process as an unprivileged app UID.

## Optimize proot-distro Storage and Bind Mounts

- Keep databases (SQLite, PostgreSQL, Redis) and Git repositories inside Termux's internal ext4/f2fs data partition (`$HOME` or inside `proot-distro` rootfs) rather than `/sdcard` (`FUSE`/`sdcardfs`). Android's `/sdcard` FUSE layer does not support POSIX file locking (`flock`), Unix domain sockets, executable bits, or symlinks reliably and is dramatically slower.
- Use `/sdcard` only for bulk media, backups, and staging exports via `--bind`:

`[NON-ROOT]` (Termux shell)

```bash
# Launch Debian with isolated host env, shared /tmp, and a dedicated non-root user
proot-distro login debian \
  --isolated \
  --shared-tmp \
  --user ops \
  --bind /sdcard/Backups:/mnt/backups
```

### Run a `proot-distro` Daemon Under Termux `runit`

You can supervise a daemon running inside Debian/Alpine directly from Termux's `termux-services`:

`[NON-ROOT]`

```bash
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
exec proot-distro login alpine -- /usr/sbin/nginx -g "daemon off;"
```

## Fix Hardcoded Shebangs Automatically

Because Android lacks `/bin/sh` and `/usr/bin/env`, third-party shell scripts fail with `bad interpreter: No such file or directory`. Rewrite shebangs across a directory with `termux-fix-shebang` (or invoke via `termux-chroot` from `proot`):

`[NON-ROOT]`

```bash
# Rewrite #!/usr/bin/env bash or #!/bin/sh to $PREFIX/bin/...
termux-fix-shebang ./scripts/*.sh
```

> **Watch out:** Running `termux-fix-shebang` inside a Git working tree modifies tracked files and dirties `git status`. For version-controlled repositories you commit back to upstream Linux hosts, install `termux-exec` (preinstalled in modern Termux) which intercepts `execve("/bin/sh", ...)` transparently via `LD_PRELOAD` without altering source files.

## Battery Temperature Watchdog via Cron

24/7 plugged-in phones without a charging controller risk thermal runaway or battery swelling. Add a lightweight thermal check using `cronie` and `termux-api` (pair this with ACC from the `root-shizuku-ops` guide if rooted):

`[NON-ROOT]` (Termux shell)

```bash
mkdir -p ~/bin
cat > ~/bin/check-thermal.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
TEMP=$(timeout 5 termux-battery-status 2>/dev/null | jq -r '.temperature // 0 | floor')
if [ "$TEMP" -ge 42 ]; then
  termux-notification \
    --id thermal-warn \
    --priority high \
    --title "Termux Server Thermal Alert" \
    --content "Battery temperature reached ${TEMP}C at $(date '+%H:%M')"
fi
EOF
chmod 700 ~/bin/check-thermal.sh

# Run every 10 minutes via cronie (ensure sv-enable crond is active)
(crontab -l 2>/dev/null; echo "*/10 * * * * $HOME/bin/check-thermal.sh") | crontab -
sv-enable crond
```
