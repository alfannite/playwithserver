# Termux Pocket Linux Troubleshooting

Symptom-to-fix matrix and recovery procedures for Android 12+ Phantom Process Killer terminations, `Termux:Boot` failures, `runit` daemon issues, SSH lockouts, and `proot-distro` errors.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Fix Process Completed Signal 9 (Phantom Process Killer)](#fix-process-completed-signal-9-phantom-process-killer)
- [Fix Termux:Boot Scripts Not Running After Reboot](#fix-termuxboot-scripts-not-running-after-reboot)
- [Fix termux-services and runit Errors](#fix-termux-services-and-runit-errors)
- [Debug OpenSSH Connection and Auth Failures](#debug-openssh-connection-and-auth-failures)
- [Fix proot-distro DNS, I/O, and Permission Errors](#fix-proot-distro-dns-io-and-permission-errors)
- [High-Signal Diagnostic One-Liners](#high-signal-diagnostic-one-liners)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause | Fix |
| --- | --- | --- | --- |
| `[Process completed (signal 9)]` | `adb shell dumpsys activity exit-info` | Android 12+ Phantom Process Killer (32-process cap) or LMKD OOM kill | Raise `max_phantom_processes` via `device_config` and disable monitor toggle |
| `Termux:Boot` script never runs | `adb logcat -d \| grep -i termux` | App never opened once, Play Store signature mismatch, or screen lock FBE | Install both from F-Droid, open `Termux:Boot` once, `chmod 700`, exempt Doze |
| `sv: warning: unable to open supervise/ok` | `pgrep -af runsvdir` | `runsvdir` not running in current session | Relaunch Termux completely or start `runsvdir -P "$PREFIX/var/service" &` |
| `ssh: Connection refused` on port 8022 | `ss -tlnp \| grep 8022` | `sshd` not running or killed by Android Doze | Start `sv up sshd`, hold `termux-wake-lock`, whitelist `com.termux` from Doze |
| `Permission denied (publickey)` | `sshd -D -d -p 8023` | Wrong permissions on `~/.ssh` or malformed `authorized_keys` | Set `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| `pkg update` fails with 403/404 or `Release` error | `cat $PREFIX/etc/apt/sources.list` | Outdated Play Store build or dead mirror | Reinstall F-Droid Termux or run `termux-change-repo` |
| `proot-distro` DNS resolution fails | `cat /etc/resolv.conf` (inside guest) | Stale or unreachable resolver inside rootfs | Write `nameserver 1.1.1.1` / `9.9.9.9` into guest `/etc/resolv.conf` |
| `CANNOT LINK EXECUTABLE: library ... not found` | `pkg upgrade` | Partial package upgrade mismatched `.so` ABI | Run full `pkg update && pkg upgrade -y` |

## Fix Process Completed Signal 9 (Phantom Process Killer)

Verify whether Android's Phantom Process Killer or Low Memory Killer (`lmkd`) terminated Termux by querying Android's process exit history over ADB:

`[NON-ROOT]` (Host workstation via ADB)

```bash
adb shell dumpsys activity exit-info | grep -A 12 'com.termux' | head -n 40
```

Look for `reason=10 (USER REQUESTED)` vs `reason=3 (LOW MEMORY)` vs `subreason=20 (EXCESSIVE CPU)` / `Kill phantom process`.

If caused by the 32-process phantom limit, re-apply and verify persistence:

`[NON-ROOT]` (Host workstation via ADB)

```bash
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
adb shell settings put global settings_enable_monitor_phantom_procs false

# Confirm active kernel/AMS limits
adb shell "/system/bin/device_config get activity_manager max_phantom_processes"
adb shell dumpsys activity settings | grep -i phantom
```

> **Watch out:** If `exit-info` reports `LOW MEMORY` (`lmkd`) rather than phantom process killing, `device_config` will not stop the kills. Reduce concurrent memory usage (for example, cap Java/Node heap sizes, switch heavy Debian workloads to Alpine, or close background Android apps) on 2–3 GB RAM devices.

## Fix Termux:Boot Scripts Not Running After Reboot

Walk through this checklist in order:

1. **Matching signatures:** Both `Termux` and `Termux:Boot` must come from F-Droid (or both from GitHub Releases). Mixing sources prevents `Termux:Boot` from accessing Termux's shared user space.
2. **Initial launch:** Open the **Termux:Boot** icon at least once after installing.
3. **File path and permissions:** Scripts must live directly in `~/.termux/boot/` (not subdirectories), have executable permissions, and use the Termux shebang:

`[NON-ROOT]` (Termux shell)

```bash
ls -la ~/.termux/boot/
head -n 1 ~/.termux/boot/*
# Expected shebang: #!/data/data/com.termux/files/usr/bin/sh
```

4. **Battery and OEM Autostart:** Verify Doze exemption via ADB (`adb shell dumpsys deviceidle whitelist | grep termux`) and disable OEM aggressive background killers (Xiaomi Autostart, Samsung Deep Sleeping Apps, Oppo/Realme Background Freeze).
5. **Debug boot script output:** Log stdout/stderr from your boot script to diagnose silent syntax errors:

`[NON-ROOT]`

```bash
#!/data/data/com.termux/files/usr/bin/sh
exec >> "$HOME/boot.log" 2>&1
echo "=== Boot start: $(date) ==="
termux-wake-lock
```

## Fix termux-services and runit Errors

### `warning: <svc>: unable to open supervise/ok: file does not exist`

`runsvdir` is either not running or has not yet noticed the symlink in `$PREFIX/var/service/`.

`[NON-ROOT]` (Termux shell)

```bash
# Check if runsvdir is running
pgrep -af runsvdir

# Check service symlinks and permissions
ls -la "$PREFIX/var/service/"
ls -la "$PREFIX/var/service/sshd/"

# Start runsvdir manually if missing
nohup runsvdir -P "$PREFIX/var/service" </dev/null >/dev/null 2>&1 &
sleep 2
sv status sshd
```

### Service Stuck in `down` or Constant 1-Second Restart Loop (`run: ... 0s` / `1s`)

Check the service's `svlogd` output or run the `run` script manually in your foreground shell to view the exact fatal error:

`[NON-ROOT]`

```bash
tail -n 50 "$PREFIX/var/log/sv/cloudflared/current"
# Or run directly to observe stderr
sh -x "$PREFIX/var/service/cloudflared/run"
```

## Debug OpenSSH Connection and Auth Failures

Start a temporary single-shot debug `sshd` instance on port `8023` while keeping production port `8022` untouched:

`[NON-ROOT]` (Termux shell)

```bash
sshd -D -d -p 8023
```

Connect from your workstation with verbose client tracing:

`[NON-ROOT]` (Workstation)

```bash
ssh -vvv -i ~/.ssh/id_ed25519_termux -p 8023 termux@192.168.1.42
```

Common findings from `-D -d`:
- `Authentication refused: bad ownership or modes for directory /data/data/com.termux/files/home/.ssh` -> Run `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`.
- `No supported authentication methods available` -> Public key is not in `~/.ssh/authorized_keys`, or file contains Windows CRLF line endings (`sed -i 's/\r$//' ~/.ssh/authorized_keys`).
- Client hangs before banner -> Android put Wi-Fi to sleep or firewall/AP isolation blocked TCP 8022. Confirm `termux-wake-lock` is held and test `nc -vz 192.168.1.42 8022`.

## Fix proot-distro DNS, I/O, and Permission Errors

### DNS Failures (`Temporary failure in name resolution`)

Inside `proot-distro`, Android's dynamic DNS resolver is not always synced into `/etc/resolv.conf`:

`[NON-ROOT]` (Inside `proot-distro`)

```bash
cat > /etc/resolv.conf <<'EOF'
nameserver 9.9.9.9
nameserver 1.1.1.1
EOF
```

### `Operation not permitted` on `ping`, `docker`, or Low Ports

`proot-distro` cannot grant Linux capabilities (`CAP_NET_RAW`, `CAP_NET_BIND_SERVICE`, `CAP_SYS_ADMIN`).
- Use `curl` or `nc` instead of `ping` for reachability checks.
- Bind web servers to ports `>= 1024` (e.g., `8080`, `8443`).
- Do not attempt to run Docker Engine (`dockerd`) inside non-root `proot-distro`.

> **Watch out:** Never run `rm -rf` on a `proot-distro` rootfs directory while a `--bind /sdcard:...` session is active or if bind mounts exist; use `proot-distro remove <distro>` cleanly after exiting all guest shells so you never delete mounted Android shared storage files.

## High-Signal Diagnostic One-Liners

`[NON-ROOT]` (Termux shell)

```bash
# Inspect all listening TCP/UDP sockets owned by Termux
ss -tulpn

# Check all termux-services states in one sweep
sv status "$PREFIX/var/service/"*

# Count current child processes under Termux (monitor against Android's 32 phantom cap)
ps -ef | wc -l

# Check memory pressure and uptime
free -h && uptime

# Verify active Termux wake-lock from host ADB
# adb shell dumpsys power | grep -i termux
```
