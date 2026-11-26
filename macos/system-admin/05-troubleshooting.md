# macOS System Administration Troubleshooting

Diagnostic matrix, `launchd` failure analysis, APFS disk space exhaustion recovery, sleep/wake debugging, and Spotlight/Homebrew repair workflows.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Symptom to Diagnostic Matrix](#symptom-to-diagnostic-matrix)
- [launchd Service Fails to Bootstrap or Crashes](#launchd-service-fails-to-bootstrap-or-crashes)
- [Disk Reports Full After Deleting Files](#disk-reports-full-after-deleting-files)
- [Unexpected Sleep or Failure to Sleep](#unexpected-sleep-or-failure-to-sleep)
- [High CPU from Spotlight or System Daemons](#high-cpu-from-spotlight-or-system-daemons)
- [Homebrew and Xcode CLT Breakage After macOS Upgrade](#homebrew-and-xcode-clt-breakage-after-macos-upgrade)
- [High-Signal Diagnostic One-Liners](#high-signal-diagnostic-one-liners)

## Symptom to Diagnostic Matrix

| Symptom | First Diagnostic Command | Likely Cause / Fix |
| :--- | :--- | :--- |
| `launchctl bootstrap` fails with `Input/output error (5)` | `plutil -lint <plist> && ls -l <plist>` | Invalid XML, wrong ownership (`root:wheel` `644`), or service is already loaded/disabled |
| `df -h` shows 100% full after deleting large files | `tmutil listlocalsnapshots /` | Local APFS Time Machine snapshots holding deleted blocks; run `tmutil thinlocalsnapshots` |
| Mac refuses to sleep or wakes randomly | `pmset -g assertions && pmset -g log \| grep "Wake from"` | Stuck power assertion (`PreventUserIdleSystemSleep`), USB HID wake, or `DarkWake` / Power Nap |
| `xcrun: error: invalid active developer path` | `xcode-select -p` | macOS upgrade invalidated CLT; reinstall via `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install` |
| `mds_stores` / `mdworker_shared` pegging CPU | `sudo fs_usage -w -f filesys mds_stores \| head -n 40` | Corrupted Spotlight index or indexing VM/build directories; exclude path or rebuild (`mdutil -E /`) |
| `brew` binary not found over SSH | `ssh host 'echo $PATH; which brew'` | Non-interactive SSH skips `~/.zprofile`; export `/opt/homebrew/bin` in `~/.zshenv` |
| Daemon launches but lacks access to `/Volumes` or Desktop | `log show --last 5m --predicate 'subsystem == "com.apple.TCC"'` | Blocked by macOS TCC (Full Disk Access); grant FDA to binary or move data to `/var`/`/opt` |
| `Too many open files` in server process | `launchctl limit maxfiles` | Low default `256` soft limit; raise via `SoftResourceLimits` in plist or `launchctl limit` |

## launchd Service Fails to Bootstrap or Crashes

### Step 1: Validate Plist Syntax and Ownership `[ROOT]`

```bash
PLIST="/Library/LaunchDaemons/com.example.worker.plist"
plutil -lint "$PLIST"
stat -f "%Sp %Su:%Sg %N" "$PLIST"
```

System daemons must output `-rw-r--r-- root:wheel`.

### Step 2: Check Disabled Overrides and Last Exit Status `[ROOT]`

A service disabled via `launchctl disable` refuses `bootstrap` with confusing errors until explicitly re-enabled.

```bash
sudo launchctl print-disabled system | grep "com.example.worker"
sudo launchctl enable system/com.example.worker

# Inspect runtime state and last exit code
sudo launchctl print system/com.example.worker | grep -E "state =|pid =|last exit code|runs ="
```

### Step 3: Decode `launchd` Error Codes and Unified Logs `[ROOT]`

```bash
# Translate numeric launchctl errno (e.g., 5, 78, 126)
launchctl error 5
launchctl error 78

# Inspect launchd's own rejection messages
log show --last 10m --predicate 'process == "launchd" AND eventMessage CONTAINS "com.example.worker"'
```

> **Watch out:** Exit code `78` (`EX_CONFIG`) means `launchd` could not execute the binary—most commonly caused by a non-executable script, a bad shebang, a missing `WorkingDirectory`, or `StandardOutPath` pointing to a directory that does not exist.

## Disk Reports Full After Deleting Files

APFS snapshots preserve deleted extents until purged.

### Step 1: Identify Local Snapshots and Purgeable Space `[ROOT]`

```bash
diskutil apfs list
tmutil listlocalsnapshots /
diskutil apfs listSnapshots /System/Volumes/Data
```

### Step 2: Thin or Remove Snapshots `[ROOT]` `[DESTRUCTIVE]`

```bash
# Request aggressive thinning of 100 GB at maximum urgency (4)
sudo tmutil thinlocalsnapshots / 100000000000 4

# Remove a stubborn individual snapshot by date stamp
sudo tmutil deletelocalsnapshots 2026-05-14-120000
```

### Step 3: Find Unlinked Open File Descriptors and Large Caches `[ROOT]`

```bash
# Processes holding deleted files open
sudo lsof +L1 | sort -k7 -rn | head -n 20

# Top space consumers under /Library and ~/Library/Caches
sudo du -sh /Library/Caches/* /private/var/vm/* /private/var/folders/* 2>/dev/null | sort -hr | head -n 15
```

> **Watch out:** Never delete `/System/Volumes/VM/sleepimage` or `/private/var/vm/swapfile*` manually while macOS is running. If swap is bloated, inspect memory pressure with `memory_pressure` and restart the leaking process (or reboot) to release swap safely.

## Unexpected Sleep or Failure to Sleep

### Diagnose Sleep Blockers `[NON-ROOT]`

```bash
# Show every process currently holding a sleep assertion
pmset -g assertions

# Inspect exact wake causes over the last 24 hours
pmset -g log | grep -E "Wake from|DarkWake|Sleep.*due to" | tail -n 30
```

Common wake reason codes:
- `RTC (Alarm)`: Scheduled wake (`pmset -g sched`) or `Power Nap` maintenance.
- `EC.LidOpen` / `HIDActivity`: External mouse/keyboard vibration or Bluetooth device.
- `Network.Host`: Wake-on-LAN (`womp`) or Bonjour Sleep Proxy (`tcpkeepalive`).

### Clear Scheduled Wake Events `[ROOT]`

```bash
pmset -g sched
sudo pmset schedule cancelall
```

## High CPU from Spotlight or System Daemons

### Pinpoint What Spotlight Is Indexing `[ROOT]`

```bash
# Watch live file paths scanned by Spotlight workers
sudo fs_usage -w -f filesys mds mds_stores mdworker_shared | head -n 40
```

### Exclude High-Churn Directories or Rebuild Index `[ROOT]`

```bash
# Exclude a build or VM directory from Spotlight cleanly
touch /Users/admin/projects/.metadata_never_index

# Disable and purge Spotlight index on an external data volume
sudo mdutil -i off /Volumes/ExternalData
sudo mdutil -X /Volumes/ExternalData

# Rebuild root volume index if metadata store is corrupted
sudo mdutil -E /
```

## Homebrew and Xcode CLT Breakage After macOS Upgrade

Major macOS updates frequently invalidate `/Library/Developer/CommandLineTools` or change SDK paths, breaking `git`, `python3`, and `brew`.

`[ROOT]` / `[NON-ROOT]`

```bash
# Reset and reinstall Xcode Command Line Tools cleanly
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install

# Verify Homebrew health and fix missing links or broken dylibs
brew doctor
brew missing
brew reinstall $(brew missing | awk -F: '{print $1}' | sort -u)
```

## High-Signal Diagnostic One-Liners

```bash
# Check memory pressure and swap usage without launching Activity Monitor
memory_pressure -Q && sysctl vm.swapusage

# List recent kernel panics and crash reports
ls -lt /Library/Logs/DiagnosticReports/ | head -n 15

# Show processes sorted by CPU and physical footprint (Apple Silicon accurate)
top -l 1 -o cpu -n 15 -stats pid,command,cpu,mem,pgrp,state

# Inspect thermal throttling or speed limit warnings
pmset -g thermlog

# Verify disk SMART status and I/O errors in kernel logs
diskutil info disk0 | grep -i "SMART"
log show --last 24h --predicate 'sender == "kernel" AND (eventMessage CONTAINS "I/O error" OR eventMessage CONTAINS "disk")'
```
