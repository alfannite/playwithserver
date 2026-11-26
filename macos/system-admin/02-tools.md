# macOS System Administration Tools

Core Darwin/macOS CLI utilities for service management, power control, APFS storage, Time Machine snapshots, unified logging, Spotlight, and diagnostics.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Tools Quick Matrix](#tools-quick-matrix)
- [launchctl (launchd Service Control)](#launchctl-launchd-service-control)
- [pmset and caffeinate (Power Management)](#pmset-and-caffeinate-power-management)
- [diskutil (APFS and Partition Management)](#diskutil-apfs-and-partition-management)
- [tmutil (Time Machine and APFS Snapshots)](#tmutil-time-machine-and-apfs-snapshots)
- [log (Unified Logging System)](#log-unified-logging-system)
- [defaults (Property List Preferences)](#defaults-property-list-preferences)
- [softwareupdate and sysdiagnose](#softwareupdate-and-sysdiagnose)
- [mdutil (Spotlight Indexing Control)](#mdutil-spotlight-indexing-control)

## Tools Quick Matrix

| Tool | Source | Domain | Primary Use Case |
| :--- | :--- | :--- | :--- |
| `launchctl` | Built-in (`/bin/launchctl`) | Init / Daemons | Bootstrap, restart, inspect, and disable `launchd` services |
| `pmset` | Built-in (`/usr/bin/pmset`) | Power | Configure sleep, wake-on-LAN, UPS, schedules, and inspect assertions |
| `caffeinate` | Built-in (`/usr/bin/caffeinate`) | Power | Temporarily prevent idle/system/disk sleep during long jobs |
| `diskutil` | Built-in (`/usr/sbin/diskutil`) | Storage / APFS | Manage APFS containers, volumes, snapshots, resize, and verification |
| `tmutil` | Built-in (`/usr/bin/tmutil`) | Backups / Snapshots | List, thin, and purge local APFS snapshots; manage exclusions |
| `log` | Built-in (`/usr/bin/log`) | Unified Logging | Query historical logs (`show`) and tail live streams (`stream`) |
| `defaults` | Built-in (`/usr/bin/defaults`) | Configuration | Read/write binary and XML `.plist` preference domains via `cfprefsd` |
| `softwareupdate` | Built-in (`/usr/sbin/softwareupdate`) | Patching | List, download, and apply macOS updates and CLT packages |
| `sysdiagnose` | Built-in (`/usr/bin/sysdiagnose`) | Diagnostics | Capture full kernel, spindump, network, and log diagnostic archive |
| `mdutil` | Built-in (`/usr/bin/mdutil`) | Spotlight | Enable, disable, or rebuild volume metadata indexes |
| `asitop` / `powermetrics` | Built-in + `brew install macmon` | Telemetry | Monitor Apple Silicon CPU/GPU/ANE power draw, thermals, and clocks |

## launchctl (launchd Service Control)

**Install:** Built-in (`/bin/launchctl`). Always use modern domain targets (`system`, `gui/<uid>`, `user/<uid>`) instead of legacy `load`/`unload`.

### High-Signal Usages `[ROOT]`

```bash
# Load and start a system daemon from /Library/LaunchDaemons/
sudo launchctl bootstrap system /Library/LaunchDaemons/com.example.worker.plist

# Unload and stop a system daemon cleanly
sudo launchctl bootout system /Library/LaunchDaemons/com.example.worker.plist

# Force-restart a running daemon without unloading its plist (-k kills existing instance)
sudo launchctl kickstart -k system/com.example.worker

# Dump full runtime state, PID, exit status, environment, and file descriptors
sudo launchctl print system/com.example.worker

# Permanently disable or re-enable a service across reboots
sudo launchctl disable system/com.example.worker
sudo launchctl enable system/com.example.worker
```

### Per-User GUI Agent Commands `[NON-ROOT]`

```bash
# Bootstrap a LaunchAgent into the active graphical user session
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.example.agent.plist

# Restart and inspect the user agent
launchctl kickstart -k "gui/$(id -u)/com.example.agent"
launchctl print "gui/$(id -u)/com.example.agent"
```

> **Watch out:** `launchctl load` and `launchctl unload` are deprecated and fail unpredictably with `Input/output error (5)` when a plist has wrong ownership or was previously disabled. System daemons in `/Library/LaunchDaemons/` must be owned by `root:wheel` with mode `0644` (`chmod 644`), or `launchctl bootstrap system` rejects them.

## pmset and caffeinate (Power Management)

**Install:** Built-in (`/usr/bin/pmset`, `/usr/bin/caffeinate`).

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Show active power assertions blocking sleep (e.g., stuck audio, backup, or display locks)
pmset -g assertions

# View sleep/wake event history and exact wake reasons (RTC, EC.PowerButton, DarkWake)
pmset -g log | grep -E "Wake from|Entering Sleep|Assertions" | tail -n 30

# Apply power settings across AC (-c), battery (-b), UPS (-u), or all (-a)
sudo pmset -c sleep 0 displaysleep 15 disksleep 0 womp 1 autorestart 1

# Keep system, disk, and network awake until a specific command exits (-i idle, -m disk, -s AC system)
caffeinate -ims rsync -aHAX /Volumes/Data/ user@backup:/srv/mac-backup/

# Keep system awake while an already-running PID finishes
caffeinate -i -w 48210
```

> **Watch out:** `pmset -g` shows the profile for the *current* power source only. Always run `pmset -g custom` to inspect AC, Battery, and UPS profiles side by side, and remember that `caffeinate -s` only prevents sleep when connected to AC power.

## diskutil (APFS and Partition Management)

**Install:** Built-in (`/usr/sbin/diskutil`).

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# List physical disks, synthesized APFS containers, and mount points
diskutil list

# Inspect APFS container space sharing, purgeable space, FileVault status, and snapshots
diskutil apfs list
diskutil apfs listSnapshots /System/Volumes/Data

# Verify an APFS volume structure online
diskutil verifyVolume /

# Reclaim free space into an APFS container after deleting a partition (0 = fill all available space)
sudo diskutil apfs resizeContainer disk0s2 0

# Create a dedicated APFS volume inside an existing container (shares pool space dynamically)
sudo diskutil apfs addVolume disk3 APFS "ContainersData"
```

> **Watch out:** `diskutil eraseDisk` and `diskutil apfs deleteContainer` are immediately `[DESTRUCTIVE]` with no confirmation prompt. Always confirm the physical vs synthesized disk identifier (`disk0` vs `disk3`) with `diskutil list` immediately prior to execution because macOS reassigns external disk numbers dynamically across reboots and reconnects.

## tmutil (Time Machine and APFS Snapshots)

**Install:** Built-in (`/usr/bin/tmutil`).

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# List all local APFS Time Machine snapshots consuming hidden disk space
tmutil listlocalsnapshots /

# Aggressively thin local snapshots to reclaim 50 GB at urgency level 4 (1-4)
sudo tmutil thinlocalsnapshots / 50000000000 4

# Delete a specific local snapshot by timestamp
sudo tmutil deletelocalsnapshots 2026-05-14-091200

# Exclude volatile directories (VMs, Docker images, build caches) from Time Machine backups
sudo tmutil addexclusion -p /Users/admin/OrbStack
sudo tmutil addexclusion -p /Users/admin/.colima
tmutil isexcluded /Users/admin/OrbStack
```

> **Watch out:** Local APFS snapshots lock deleted files on disk until thinned, causing `df -h` to report a full root filesystem even after deleting tens of gigabytes of files. `tmutil addexclusion -p` creates a fixed-path exclusion stored in `/Library/Preferences/com.apple.TimeMachine.plist` (requires `[ROOT]`), whereas omitting `-p` writes a sticky `com.apple.metadata:com_apple_backup_excludeItem` xattr that moves with the folder.

## log (Unified Logging System)

**Install:** Built-in (`/usr/bin/log`). Replaces legacy `/var/log/system.log` for nearly all modern macOS subsystems.

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Query the last 30 minutes of logs for a specific process with info and debug messages
log show --last 30m --info --predicate 'process == "sshd" OR process == "mDNSResponder"'

# Filter by subsystem and category across an exact time window
log show --start "2026-05-14 08:00:00" --end "2026-05-14 09:00:00" \
  --predicate 'subsystem == "com.apple.TimeMachine" AND messageType >= 16'

# Stream real-time kernel and launchd errors with compact formatting
log stream --style compact --level error --predicate 'sender == "kernel" OR process == "launchd"'

# Export a 1-hour logarchive for offline analysis
sudo log collect --last 1h --output /tmp/incident.logarchive
```

> **Watch out:** Unified logging censors dynamic strings as `<private>` by default unless a configuration profile enables private data logging or the predicate matches public fields. Additionally, `log show` without `--last` or `--start` scans the entire persisted log store and can take minutes while consuming gigabytes of RAM.

## defaults (Property List Preferences)

**Install:** Built-in (`/usr/bin/defaults`). For complex nested arrays/dictionaries, pair with `/usr/libexec/PlistBuddy`.

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Read all keys in a domain or a single key
defaults read com.apple.finder
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled

# Search across all preference domains for a keyword
defaults find "Sleep"

# Write typed values (-bool, -int, -string, -array)
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write NSGlobalDomain KeyRepeat -int 2

# Delete a custom override to restore Apple default behavior
defaults delete com.apple.finder AppleShowAllFiles
```

> **Watch out:** Editing a `.plist` file directly with `vim` or `sed` is silently overwritten by `cfprefsd`, which caches preferences in memory. Always modify preferences via `defaults` (which notifies `cfprefsd`), or run `killall cfprefsd` after modifying raw files with `PlistBuddy`.

## softwareupdate and sysdiagnose

**Install:** Built-in (`/usr/sbin/softwareupdate`, `/usr/bin/sysdiagnose`).

### High-Signal Usages `[ROOT]`

```bash
# List available macOS updates without installing
softwareupdate --list

# Download updates in background without rebooting yet
sudo softwareupdate --download --all

# Fetch a full macOS installer app to /Applications for clean rebuilds or VMs
softwareupdate --fetch-full-installer --full-installer-version 15.4

# Capture a non-interactive diagnostic bundle without launching Finder (-u skips Finder reveal)
sudo sysdiagnose -u -f /tmp/
```

> **Watch out:** Running `softwareupdate --install` on Apple Silicon requires Volume Owner credentials (a Secure Token / Bootstrap Token user password) for major and minor macOS point releases, which breaks unattended SSH updates unless MDM manages updates or credentials are supplied interactively.

## mdutil (Spotlight Indexing Control)

**Install:** Built-in (`/usr/bin/mdutil`).

### High-Signal Usages `[ROOT]`

```bash
# Show indexing status on all mounted volumes
mdutil -sa

# Disable Spotlight indexing on an external backup or VM storage volume
sudo mdutil -i off /Volumes/NVMe-VMs
sudo mdutil -d /Volumes/NVMe-VMs

# Erase and rebuild a corrupted Spotlight index on the boot volume
sudo mdutil -E /
```

> **Watch out:** Disabling Spotlight globally on `/` (`sudo mdutil -a -i off`) also breaks macOS Mail search, Finder tag queries, and several System Settings search panels. On servers, exclude high-churn external data volumes individually (`mdutil -i off /Volumes/<name>`) or drop an empty `.metadata_never_index` file at the volume root.
