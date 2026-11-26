# Headless Mac Server Tips and Tricks

Practical patterns for surviving unattended reboots, preventing external Thunderbolt/USB4 NVMe disconnects, optimizing headless GPU/Screen Sharing, isolating server data volumes, and keeping container services alive 24/7.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Solving the FileVault Unattended Reboot Trap](#solving-the-filevault-unattended-reboot-trap)
- [Preventing External Thunderbolt and USB4 NVMe Disconnects](#preventing-external-thunderbolt-and-usb4-nvme-disconnects)
- [Headless Screen Sharing Without Lag](#headless-screen-sharing-without-lag)
- [Mounting External Volumes Before User Login](#mounting-external-volumes-before-user-login)
- [Auto-Starting User-Session Services Safely After Reboot](#auto-starting-user-session-services-safely-after-reboot)
- [UPS Graceful Shutdown and Power Draw Profiling](#ups-graceful-shutdown-and-power-draw-profiling)

## Solving the FileVault Unattended Reboot Trap

When FileVault is enabled on the macOS boot volume, the system halts at the pre-boot EFI/iBoot login screen after any reboot or power failure. Neither `sshd`, `tailscaled`, nor any `LaunchDaemon` starts until a Volume Owner enters a password on a physically attached keyboard.

### Three Production Strategies

| Strategy | Unattended Power-Loss Recovery | Data-at-Rest Protection | Best Use Case |
| :--- | :--- | :--- | :--- |
| **1. `fdesetup authrestart`** | Planned reboots only (fails on power cut) | Full boot + data volume encryption | Servers on dual-UPS / supervised colocation |
| **2. Split Encrypted APFS Data Volume** | 100% unattended boot into SSH + Tailscale | Sensitive data encrypted; OS volume unencrypted | Best balance for remote homelab / closet Mac Minis |
| **3. Hardware IP-KVM (PiKVM / NanoKVM)** | Manual remote unlock over out-of-band KVM | Full FileVault encryption on all volumes | High-security colocation or untrusted physical premises |

### Implementing Strategy 1: Authenticated Planned Reboot `[ROOT]` `[REBOOT]`

```bash
# Reboots once and unlocks FileVault automatically using a single-use key held in SMC/SEP
sudo fdesetup authrestart
```

### Implementing Strategy 2: Unencrypted Boot Volume + Encrypted APFS Data Volume `[ROOT]`

Keep FileVault disabled on `/` so macOS boots straight into `sshd` and `tailscaled`, while storing databases, Docker volumes, secrets, and backups on a separate APFS Encrypted volume unlocked via SSH after boot.

```bash
# Create an encrypted APFS volume inside the internal container (or external NVMe container)
sudo diskutil apfs addVolume disk3 "APFS (Encrypted)" "ServerVault" -passphrase

# After an unattended reboot, SSH in and unlock the data volume manually, then start dependent daemons
sudo diskutil apfs unlockVolume "ServerVault"
sudo launchctl kickstart -k system/com.example.postgres
```

> **Watch out:** Never store an encrypted volume's passphrase in plaintext inside `/Library/LaunchDaemons/`—that defeats encryption completely. Unlock `ServerVault` interactively over SSH after reboot, or fetch the unlock key from an external Vault/KMS over mTLS.

## Preventing External Thunderbolt and USB4 NVMe Disconnects

macOS frequently triggers *"Disk Not Ejected Properly"* on external NVMe drives during idle power transitions, bus power dips, or Spotlight/Time Machine I/O bursts.

### Stability Checklist `[ROOT]`

```bash
# 1. Disable disk sleep and power nap globally
sudo pmset -a disksleep 0 sleep 0 powernap 0

# 2. Disable Spotlight indexing on external server storage volumes
sudo mdutil -i off /Volumes/NVMe-Pool
touch /Volumes/NVMe-Pool/.metadata_never_index

# 3. Exclude external VM/container disks from Time Machine
sudo tmutil addexclusion -p /Volumes/NVMe-Pool
```

### Keep External Enclosures Awake Under Aggressive Controller Firmware `[ROOT]`

Some USB/Thunderbolt bridges implement internal controller sleep regardless of macOS `pmset disksleep 0`. Deploy a lightweight `LaunchDaemon` that touches a hidden keepalive file every 240 seconds:

```bash
# Example keepalive command inside a LaunchDaemon with StartInterval = 240
/bin/sh -c '[ -d /Volumes/NVMe-Pool ] && /usr/bin/touch /Volumes/NVMe-Pool/.keepalive'
```

> **Watch out:** Avoid passive bus-powered USB-C hubs between a Mac Mini and NVMe drives. Connect Thunderbolt/USB4 NVMe enclosures directly to the Mac Mini's rear Thunderbolt ports using certified short (<= 0.8 m) USB4/Thunderbolt 4 cables.

## Headless Screen Sharing Without Lag

When using an HDMI EDID dummy plug (or `BetterDisplay` virtual screen), tune Screen Sharing for sharp text and low bandwidth over Tailscale:

1. Use an HDMI dummy plug supporting 1920x1080 or 2560x1440 at 60Hz (avoid cheap 4K@30Hz-only plugs that stutter).
2. Enable **High Performance** mode in Apple's native Screen Sharing app on macOS Sonoma/Sequoia when connecting from another Apple Silicon Mac over wired LAN or direct Tailscale WireGuard.
3. Keep `displaysleep 0` set so the virtual display never suspends the WindowServer compositor.

## Mounting External Volumes Before User Login

By default, macOS waits until a GUI user logs in before auto-mounting external drives. For a 24/7 server hosting Docker volumes or Plex/Jellyfin libraries on external NVMe, enable boot-time mounting via `autodiskmount`.

`[ROOT]`

```bash
# Enable mounting of external/removable volumes before GUI login
sudo defaults write /Library/Preferences/SystemConfiguration/autodiskmount AutomountDisksWithoutUserLogin -bool true
```

For deterministic mount points (preventing `/Volumes/Data 1` collisions), bind the volume by UUID in `/etc/fstab` via `sudo vifs`:

```text
# Retrieve UUID via: diskutil info /Volumes/NVMe-Pool | grep "Volume UUID"
UUID=12345678-ABCD-4321-EFGH-0123456789AB /Volumes/NVMe-Pool apfs rw,auto
```

## Auto-Starting User-Session Services Safely After Reboot

Tools like OrbStack, Colima (without root), and GUI media apps require an active `gui/<uid>` session. If your threat model allows an unencrypted boot volume (Strategy 2 above) in a physically secured closet, you can enable auto-login for a non-admin service user and immediately lock the console screen on login via a `LaunchAgent`:

`[NON-ROOT]`

```bash
# Command executed by ~/Library/LaunchAgents/com.local.lockscreen.plist with RunAtLoad=true
/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine
```

This starts the `gui/<uid>` session so OrbStack/Colima launch immediately after power recovery while keeping the physical console locked.

## UPS Graceful Shutdown and Power Draw Profiling

An Apple Silicon Mac Mini idles at **5–7 W** and pulls **30–65 W** under heavy container/VM load, running for hours on a compact 600VA UPS.

`[ROOT]`

```bash
# Configure native macOS UPS shutdown thresholds (no third-party daemon required for HID USB UPS)
sudo pmset -u haltlevel 20     # Clean shutdown at 20% battery remaining
sudo pmset -u haltafter 10     # Or after 10 minutes on battery
sudo pmset -u haltremain 5     # Or when 5 minutes of runtime remain

# Inspect UPS telemetry detected by macOS
pmset -g batt
pmset -g ups
```
