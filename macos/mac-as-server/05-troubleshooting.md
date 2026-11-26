# Headless Mac Server Troubleshooting

Symptom-to-fix matrix and deep-dive recovery playbooks for unreachable headless Mac Minis, FileVault reboot lockouts, external NVMe disconnects, sluggish Screen Sharing, and OrbStack/Colima container failures.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Symptom to Diagnostic Matrix](#symptom-to-diagnostic-matrix)
- [Server Unreachable After Reboot or Power Outage](#server-unreachable-after-reboot-or-power-outage)
- [External Thunderbolt or USB4 NVMe Disconnects Randomly](#external-thunderbolt-or-usb4-nvme-disconnects-randomly)
- [Screen Sharing Is Blank, Frozen, or Extremely Laggy](#screen-sharing-is-blank-frozen-or-extremely-laggy)
- [OrbStack or Colima Containers Fail to Start After Reboot](#orbstack-or-colima-containers-fail-to-start-after-reboot)
- [High Idle Power, Fan Noise, or Thermal Throttling](#high-idle-power-fan-noise-or-thermal-throttling)
- [High-Signal Headless Server Diagnostic One-Liners](#high-signal-headless-server-diagnostic-one-liners)

## Symptom to Diagnostic Matrix

| Symptom | First Diagnostic Command | Likely Cause / Fix |
| :--- | :--- | :--- |
| Host dead over SSH/Tailscale right after reboot | Check router ARP/DHCP lease & physical HDMI output | FileVault halted at pre-boot unlock screen; unlock locally or switch to split encrypted APFS data volume |
| SSH works, but Docker/OrbStack/Tailscale GUI did not start | `who && launchctl print-disabled system` | Service installed as `LaunchAgent` (`~/Library/LaunchAgents`) instead of `LaunchDaemon`; needs GUI login or root daemon |
| External NVMe unmounts or becomes `/Volumes/Data 1` | `log show --last 24h --predicate 'sender == "kernel" AND eventMessage CONTAINS "USB\|Thunderbolt\|disk"'` | Disk sleep enabled, faulty cable/enclosure, or stale mount folder in `/Volumes/`; set `disksleep 0` and clean stale dir |
| Screen Sharing connects to black screen or tiny 1024x768 | `system_profiler SPDisplaysDataType` | No HDMI EDID dummy plug detected; attach dummy plug and restart WindowServer or Screen Sharing agent |
| Colima fails with `VZError` or slow bind mounts | `colima status && colima logs` | Running QEMU/sshfs or exceeding macOS 2-VM limit; recreate with `--vm-type vz --mount-type virtiofs` |
| `diskutil apfs list` shows external drive not mounted after boot | `defaults read /Library/Preferences/SystemConfiguration/autodiskmount` | `AutomountDisksWithoutUserLogin` not set to `true`; enable and bind UUID in `/etc/fstab` |
| `tailscale status` offline after reboot | `sudo brew services list \| grep tailscale` | Using GUI App Store Tailscale instead of `tailscaled` LaunchDaemon; migrate to system daemon |
| Port 22 reachable on LAN but unreachable over Tailscale | `sudo pfctl -a com.local.server -sr && scutil --nwi` | PF blocking `utun*` or Tailscale subnet not in `lan_admin` macro |

## Server Unreachable After Reboot or Power Outage

### Triage Sequence

1. **Check L2/L3 network presence from another LAN machine:**
   ```bash
   ping -c 3 192.168.10.50
   arp -an | grep 192.168.10.50
   ```
2. **If ping fails completely:**
   - **Cause A (FileVault pre-boot halt):** The Mac booted to the FileVault password screen where macOS networking and `sshd` are not yet initialized. Attach a monitor/keyboard (or IP-KVM) to unlock. To prevent recurrence on planned reboots, use `sudo fdesetup authrestart`; for unattended power-loss survival, move encryption to a secondary APFS Encrypted data volume.
   - **Cause B (`autorestart 0`):** Power returned after an outage, but the Mac stayed powered off. Once back online, confirm `pmset -g custom | grep autorestart` outputs `1` and verify with `sudo systemsetup -getrestartpowerfailure`.
3. **If ping works, but SSH (`22`) times out or refuses connection:**
   - Verify whether a `pf` anchor loaded before `en0` acquired DHCP (use dynamic interface syntax `($ext_if)` in PF rules rather than hardcoded static rules that fail at boot if DHCP is slow).
   - Verify `sshd` state once console access is restored:
     ```bash
     sudo systemsetup -getremotelogin
     sudo launchctl print system/com.openssh.sshd | head -n 25
     ```

## External Thunderbolt or USB4 NVMe Disconnects Randomly

### Step 1: Inspect Kernel Storage and Bus Disconnect Logs `[ROOT]`

```bash
log show --last 24h --predicate 'sender == "kernel" AND (eventMessage CONTAINS "disk" OR eventMessage CONTAINS "NVMe" OR eventMessage CONTAINS "Thunderbolt" OR eventMessage CONTAINS "ejected")' --style compact | tail -n 40
```

### Step 2: Check Drive SMART Health and Stale `/Volumes` Mount Points `[ROOT]`

```bash
# Check for orphaned duplicate mount folders like "/Volumes/NVMe-Pool 1"
ls -la /Volumes/

# Inspect SMART temperature and media error counters on the external disk
diskutil list external
sudo smartctl -a /dev/disk4 | grep -E "Temperature|Media and Data|Error Information|Percentage Used"
```

### Step 3: Repair Dirty APFS Filesystem After Unexpected Eject `[ROOT]`

```bash
# Unmount cleanly if partially mounted, then run APFS verification/repair
sudo diskutil unmountDisk /dev/disk4
sudo diskutil repairVolume /dev/disk4s1
sudo diskutil mountDisk /dev/disk4
```

> **Watch out:** Never run `rm -rf /Volumes/NVMe-Pool` while a volume is mounted! First confirm with `mount | grep NVMe-Pool` that nothing is mounted at the stale directory path, then remove the empty stale mount directory safely with `sudo rmdir "/Volumes/NVMe-Pool"`.

## Screen Sharing Is Blank, Frozen, or Extremely Laggy

### Step 1: Verify Virtual/Dummy Display Detection Over SSH `[NON-ROOT]`

```bash
system_profiler SPDisplaysDataType
```

If `Displays:` is missing or shows `No Display Connected`, macOS has fallen back to unaccelerated headless mode. Reseat or replace the HDMI EDID dummy plug.

### Step 2: Restart Screen Sharing and ARD Agents Without Rebooting `[ROOT]`

```bash
# Restart screensharingd cleanly
sudo launchctl kickstart -k system/com.apple.screensharing

# Restart ARD Agent if using Remote Management
KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
sudo "$KICKSTART" -restart -agent
```

### Step 3: Verify SSH Tunnel Binding `[NON-ROOT]`

```bash
# On the Mac Mini, confirm port 5900 is actually listening
sudo lsof -nP -iTCP:5900 -sTCP:LISTEN

# On your client workstation, verify local forward port 15900 is bound
lsof -nP -iTCP:15900 -sTCP:LISTEN
```

## OrbStack or Colima Containers Fail to Start After Reboot

### Diagnosing OrbStack `[NON-ROOT]`

```bash
orb status
orb logs | tail -n 50
docker context ls
docker ps -a
```

If `docker ps` returns `Cannot connect to the Docker daemon at unix:///Users/admin/.orbstack/run/docker.sock`, start the runtime (`orb start`) and check whether your user GUI session is active (`who`).

### Diagnosing Colima `[NON-ROOT]`

```bash
colima status
colima list
tail -n 60 ~/.colima/_lima/colima/ha.stderr.log

# Recover from a wedged Lima/VZ VM state without deleting container data volumes
colima stop --force
colima start --vm-type vz --mount-type virtiofs
```

> **Watch out:** Running `colima delete` is `[DESTRUCTIVE]` and destroys the entire Linux VM disk image, including all unnamed Docker volumes and local images inside Colima. Always back up bind mounts or export volumes before running `colima delete`.

## High Idle Power, Fan Noise, or Thermal Throttling

### Identify Runaway Processes and Power Consumers `[ROOT]`

```bash
# Sample CPU/GPU power draw and thermal pressure over 3 seconds (Apple Silicon)
sudo powermetrics --samplers cpu_power,gpu_power,thermal -n 3 -i 1000

# Top 15 CPU consumers and physical memory footprint
top -l 1 -o cpu -n 15 -stats pid,command,cpu,mem,state

# Check for background Spotlight or Time Machine churn
pmset -g assertions
tmutil status
```

## High-Signal Headless Server Diagnostic One-Liners

```bash
# Full server health snapshot (uptime, power profile, storage, listening ports)
uptime && pmset -g custom | grep -E "sleep|autorestart|womp" && df -h / /Volumes/* 2>/dev/null

# Verify boot-time LaunchDaemons vs user-only LaunchAgents
sudo launchctl list | grep -v "com.apple"
launchctl list | grep -v "com.apple"

# Check recent unexpected reboots, shutdown causes, and kernel panics
log show --last 7d --predicate 'eventMessage CONTAINS "Previous shutdown cause"' --style compact
ls -lt /Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -n 10

# Inspect APFS container health and external drive mount status
diskutil apfs list | grep -E "Container|Volume|Mount Point|FileVault|Capacity"
```
