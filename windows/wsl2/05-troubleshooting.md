# WSL2 Troubleshooting

Symptom-driven diagnostic matrix and incident workflows for WSL2 on Windows 10/11: VPN DNS resolution breakage, mirrored networking edge cases, runaway `vmmem` RAM usage, bloated `ext4.vhdx` disk exhaustion, clock drift after sleep/hibernate, `systemd` startup failures, and `usbipd-win` attachment errors.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Quick Matrix](#symptom-to-fix-quick-matrix)
- [VPN DNS and Mirrored Networking Failures](#vpn-dns-and-mirrored-networking-failures)
- [High vmmem RAM Usage and Disk Space Exhaustion](#high-vmmem-ram-usage-and-disk-space-exhaustion)
- [Clock Drift After Sleep or Hibernate](#clock-drift-after-sleep-or-hibernate)
- [systemd Startup and Interop Failures](#systemd-startup-and-interop-failures)
- [usbipd-win Attachment and Permission Errors](#usbipd-win-attachment-and-permission-errors)
- [WSL2 Startup Crash and Virtualization Errors](#wsl2-startup-crash-and-virtualization-errors)
- [High-Signal Triage One-Liners](#high-signal-triage-one-liners)

## Symptom-to-Fix Quick Matrix

| Symptom | Primary Diagnostic Command | Root Cause / Fix |
| --- | --- | --- |
| DNS fails inside WSL2 whenever corporate VPN connects | `cat /etc/resolv.conf` and `dig github.com` | NAT-mode DNS proxy broken by VPN split-tunnel; enable `networkingMode=mirrored` + `dnsTunneling=true` in `.wslconfig` |
| `vmmem` / `vmmemWSL` consumes 16+ GB RAM continuously | `free -h` inside WSL2 & inspect `%USERPROFILE%\.wslconfig` | Missing `memory=` cap or `autoMemoryReclaim=gradual`; configure `.wslconfig` and run `wsl --shutdown` |
| `ext4.vhdx` stays 80 GB after deleting files in Linux | `Get-Item D:\WSL\Debian\ext4.vhdx` | VHDX does not auto-shrink without sparse mode; run `fstrim /`, `wsl --shutdown`, and `Optimize-VHD -Mode Full` |
| `apt update` fails with "Release file is not valid yet" / TLS errors | `date -u` vs Windows `(Get-Date).ToUniversalTime()` | Clock drift after Windows Modern Standby/hibernate; run `sudo hwclock -s` |
| `systemctl` fails with `System has not been booted with systemd` | `ps -p 1 -o comm=` and `cat /etc/wsl.conf` | Missing `[boot] systemd=true` in `/etc/wsl.conf` or distro not terminated after edit |
| `wsl --import` logs in as `root` instead of normal user | `whoami` and `cat /etc/wsl.conf` | Import resets default user; add `[user] default=<name>` to `/etc/wsl.conf` and `wsl --terminate` |
| `usbipd attach --wsl` fails with firewall or kernel error | `usbipd list` and `dmesg \| tail` inside WSL2 | Host firewall blocking TCP 3240 (USB/IP) or stale WSL kernel; run `wsl --update` |
| `WslRegisterDistribution failed with error: 0x80370102` | `bcdedit /enum` & `Get-WindowsOptionalFeature` | Nested virtualization/BIOS VT-x disabled or `hypervisorlaunchtype` is `Off` |

## VPN DNS and Mirrored Networking Failures

Corporate VPNs (Cisco AnyConnect, GlobalProtect, WireGuard, Zscaler) frequently break legacy WSL2 NAT DNS resolution (`Temporary failure in name resolution`) or drop MTU-oversized packets.

### Preferred Fix (Windows 11 22H2+ / WSL 2.0+) `[NON-ROOT]`

Configure `%USERPROFILE%\.wslconfig` with mirrored networking and DNS tunneling (routes Linux DNS queries through Windows' own resolver stack, respecting VPN NRPT rules and proxies):

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
```

Restart WSL2 (`wsl --shutdown`) and test:

```bash
cat /etc/resolv.conf
dig +short internal.corp.example.com
curl -I https://github.com
```

### Fallback Fix (Windows 10 or When VPN Breaks Mirrored Mode) `[ROOT]`

If mirrored mode conflicts with a legacy VPN client (e.g., Cisco AnyConnect blocking Hyper-V mirrored adapters), switch back to NAT mode, disable automatic `/etc/resolv.conf` generation, and pin working DNS servers + lower MTU:

```bash
# 1. Disable automatic resolv.conf overwrite in /etc/wsl.conf
sudo tee -a /etc/wsl.conf > /dev/null <<'EOF'
[network]
generateResolvConf=false
EOF

# 2. Replace symlinked /etc/resolv.conf with explicit DNS servers (your VPN DNS + fallback)
sudo rm -f /etc/resolv.conf
sudo tee /etc/resolv.conf > /dev/null <<'EOF'
nameserver 10.20.10.5
nameserver 1.1.1.1
options timeout:2 attempts:2
EOF

# 3. If HTTPS hangs after TLS ClientHello over VPN, test lowering eth0 MTU to 1350
sudo ip link set dev eth0 mtu 1350
```

> **Watch out:** Deleting `/etc/resolv.conf` without setting `generateResolvConf=false` in `/etc/wsl.conf` only lasts until the next `wsl --shutdown`, when WSL2 regenerates the symlink. Conversely, if you later re-enable `dnsTunneling=true`, revert `generateResolvConf=true` or DNS tunneling will not take effect.

## High vmmem RAM Usage and Disk Space Exhaustion

### Diagnose and Reclaim RAM `[NON-ROOT]` / `[ROOT]`

```powershell
# On Windows: inspect vmmemWSL working set RAM
Get-Process vmmem* -ErrorAction SilentlyContinue |
    Select-Object Name, Id, @{N='RAM_GB';E={[math]::Round($_.WorkingSet64/1GB,2)}}
```

```bash
# Inside WSL2: check whether RAM is active processes vs reclaimable Linux page cache (buff/cache)
free -h

# Drop Linux page cache immediately without killing running shells/containers
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
```

### Diagnose and Reclaim ext4.vhdx Disk Space `[ROOT]`

```bash
# Inside WSL2: find largest directories consuming ext4 space (often /var/lib/docker or ~/.cache)
sudo du -xhd 1 / 2>/dev/null | sort -h
docker system df 2>/dev/null
sudo fstrim -v /
```

Then compact the VHDX on Windows (`[ROOT]`):

```powershell
wsl --shutdown
Optimize-VHD -Path "D:\WSL\Debian\ext4.vhdx" -Mode Full
```

## Clock Drift After Sleep or Hibernate

When a Windows laptop sleeps or hibernates, the WSL2 VM clock can fall behind wall-clock time by hours, breaking `apt`, AWS/GCP API signatures, Kerberos, and TLS certificate validation.

`[ROOT]`
```bash
# Compare WSL2 UTC clock against Windows host UTC clock
date -u
powershell.exe -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('u')"

# Sync Linux system clock immediately from the Hyper-V hardware clock
sudo hwclock -s

# Verify drift is resolved
date -u
```

> **Watch out:** Do not install `chrony` or `systemd-timesyncd` to fight the Hyper-V clock unless you know `hv_utils` is disabled; on modern WSL 2.x kernels, `wsl --update` fixes most suspend/resume drift automatically, and `sudo hwclock -s` provides an instant zero-dependency resync.

## systemd Startup and Interop Failures

`[ROOT]`
```bash
# 1. Verify systemd is PID 1 and list any failed units slowing down WSL2 boot
ps -p 1 -o pid,comm
systemctl --failed
systemd-analyze blame | head -n 15

# 2. If running Windows executables (code, explorer.exe) fails with "Exec format error" or "cannot execute binary file"
# Check that WSLInterop binfmt_misc handler is registered (systemd-binfmt can wipe it on some distros!)
cat /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null || echo "WSLInterop missing!"

# 3. Permanently protect WSLInterop from systemd-binfmt wipe on Debian/Ubuntu
sudo tee /etc/binfmt.d/WSLInterop.conf > /dev/null <<'EOF'
:WSLInterop:M::MZ::/init:PF
EOF
sudo systemctl restart systemd-binfmt
```

> **Watch out:** On some Debian and Arch WSL2 installations with `systemd=true`, `systemd-binfmt.service` clears `/proc/sys/fs/binfmt_misc/WSLInterop` during boot, breaking every Windows `.exe` invocation from Linux (`code .`, `clip.exe`, `powershell.exe`). Creating `/etc/binfmt.d/WSLInterop.conf` fixes it permanently.

## usbipd-win Attachment and Permission Errors

`[ROOT]`
```powershell
# 1. Inspect device state and ensure usbipd Windows service is running
Get-Service usbipd | Select-Object Name, Status, StartType
usbipd list

# 2. If attach hangs or fails with connection refused, verify TCP 3240 is allowed on WSL/vEthernet interface
Get-NetFirewallRule -DisplayName "*usbipd*" | Format-Table DisplayName, Enabled, Action, Profile
```

Inside Linux, if `/dev/ttyUSB0` attaches but your non-root user gets `Permission denied`:

`[ROOT]`
```bash
# Add user to dialout/plugdev groups so serial adapters and USB programmers work without sudo
sudo usermod -aG dialout,plugdev "$USER"
# Re-open WSL2 shell (or wsl --terminate <Distro>) to refresh group membership
```

## WSL2 Startup Crash and Virtualization Errors

When `wsl` fails to launch with `0x80370102` (Virtual machine could not be started) or `HCS_E_SERVICE_NOT_AVAILABLE`:

`[ROOT]` `[REBOOT]`
```powershell
# 1. Verify required Windows features are Enabled
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux, VirtualMachinePlatform |
    Format-Table FeatureName, State

# 2. Verify Hypervisor is configured to launch at boot (must show hypervisorlaunchtype Auto)
bcdedit /enum '{current}' | Select-String "hypervisorlaunchtype"
# Fix if Off:
# bcdedit /set hypervisorlaunchtype Auto

# 3. Verify WSL and Host Compute Service (vmcompute) are running
Get-Service LxssManager, WSLService, vmcompute -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType

# 4. Restart Host Compute Service if hung after a crash
Restart-Service vmcompute -Force
```

## High-Signal Triage One-Liners

Windows host (`[NON-ROOT]` / `[ROOT]`):

```powershell
# Show all registered WSL distros, their exact VHDX paths, and VHDX size in GB
Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    $vhdx = Join-Path $p.BasePath "ext4.vhdx"
    $sizeGB = if (Test-Path $vhdx) { [math]::Round((Get-Item $vhdx).Length / 1GB, 2) } else { 0 }
    [PSCustomObject]@{ Distro = $p.DistributionName; Version = $p.Version; VHDX_GB = $sizeGB; Path = $p.BasePath }
} | Format-Table -AutoSize

# Check WSL2 diagnostic logs / version / active networking state
wsl --status
wsl --version
```

Inside WSL2 Linux (`[NON-ROOT]`):

```bash
# Rapid environment health snapshot (PID 1, kernel, RAM, disk, IP, DNS)
printf "PID1=%s | Kernel=%s\n" "$(ps -p 1 -o comm=)" "$(uname -r)"
free -h | awk 'NR<=2'
df -h / | awk 'NR==2{print "RootFS:", $3 "/" $2, "("$5")"}'
ip -br -4 addr
grep '^nameserver' /etc/resolv.conf
```
