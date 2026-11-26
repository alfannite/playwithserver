# macOS System Administration Tips and Tricks

High-leverage `launchd` templates, APFS maintenance patterns, kernel/sysctl tuning, `defaults` workflow optimizations, and Darwin behavioral quirks.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Production launchd System Daemon Template](#production-launchd-system-daemon-template)
- [File Descriptor and Process Limits](#file-descriptor-and-process-limits)
- [APFS Space Reclamation and Sparse Files](#apfs-space-reclamation-and-sparse-files)
- [High-Value defaults Tweaks](#high-value-defaults-tweaks)
- [Clipboard, Spotlight, and Metadata Quirks](#clipboard-spotlight-and-metadata-quirks)
- [Apple Silicon Telemetry Without Root Overhead](#apple-silicon-telemetry-without-root-overhead)

## Production launchd System Daemon Template

Never run services in the background with `daemonize` or `&` under `launchd`; `launchd` requires foreground processes and will respawn endlessly if a daemon forks and exits.

### Minimal Hardened Plist (`/Library/LaunchDaemons/com.example.exporter.plist`) `[ROOT]`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.exporter</string>

  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/node_exporter</string>
    <string>--web.listen-address=127.0.0.1:9100</string>
  </array>

  <key>UserName</key>
  <string>_exporter</string>
  <key>GroupName</key>
  <string>_exporter</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>

  <key>ThrottleInterval</key>
  <integer>10</integer>

  <key>WorkingDirectory</key>
  <string>/var/empty</string>

  <key>StandardOutPath</key>
  <string>/var/log/node_exporter.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/node_exporter.err.log</string>
</dict>
</plist>
```

### Validate, Set Permissions, and Bootstrap `[ROOT]`

```bash
plutil -lint /Library/LaunchDaemons/com.example.exporter.plist
sudo chown root:wheel /Library/LaunchDaemons/com.example.exporter.plist
sudo chmod 644 /Library/LaunchDaemons/com.example.exporter.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.example.exporter.plist
```

| Plist Key | Effect | Operational Guidance |
| :--- | :--- | :--- |
| `RunAtLoad` | Starts immediately upon `bootstrap` / boot | Pair with `KeepAlive` for long-running daemons |
| `KeepAlive` (`SuccessfulExit: false`) | Restarts only on non-zero exit | Prevents restart loops if service shuts down cleanly |
| `ThrottleInterval` | Minimum seconds between restarts (default `10`) | Prevents CPU burn on misconfigured services |
| `SoftResourceLimits` / `HardResourceLimits` | Sets `NumberOfFiles` (`ulimit -n`) per daemon | Required for Nginx, databases, and high-concurrency Go apps |
| `ProcessType` | `Background`, `Standard`, `Adaptive`, `Interactive` | Set `Interactive` or `Standard` so macOS does not throttle CPU/IO to efficiency cores |

> **Watch out:** macOS `launchd` defaults to `ProcessType: Background` for many background jobs and pins them aggressively to Apple Silicon Efficiency (E) cores under thermal or scheduling pressure. Set `<key>ProcessType</key><string>Interactive</string>` or `Standard` for latency-sensitive daemons.

## File Descriptor and Process Limits

macOS ships with a conservative default soft limit (`ulimit -n` = `256` in many shells), which breaks build tools, PostgreSQL, and Node/Go servers.

### Inspect and Raise Limits `[ROOT]`

```bash
# View current system-wide launchd limits
launchctl limit maxfiles
sysctl kern.maxfiles kern.maxfilesperproc

# Raise system limits dynamically (valid until reboot)
sudo launchctl limit maxfiles 65536 524288
```

### Persist Limits Across Reboots via LaunchDaemon `[ROOT]`

Create `/Library/LaunchDaemons/limit.maxfiles.plist` with `ProgramArguments`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>limit.maxfiles</string>
  <key>ProgramArguments</key>
  <array>
    <string>launchctl</string>
    <string>limit</string>
    <string>maxfiles</string>
    <string>65536</string>
    <string>524288</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

> **Watch out:** Setting `maxfiles` to `unlimited` fails silently or caps at kernel `kern.maxfilesperproc` on modern macOS. Always use explicit numeric soft and hard values (such as `65536 524288`) and verify with `launchctl limit maxfiles` after reboot.

## APFS Space Reclamation and Sparse Files

### Instant Copy-on-Write Clones `[NON-ROOT]`

Use `cp -c` to clone multi-gigabyte VM disks or build artifacts instantaneously with zero extra APFS block consumption until modified.

```bash
cp -c /Volumes/Data/base-ubuntu.img /Volumes/Data/test-ubuntu.img
```

### Prevent `.DS_Store` and AppleDouble `._*` Pollution `[NON-ROOT]`

```bash
# Stop Finder from writing .DS_Store files on SMB/NFS/USB shares
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Prevent macOS tar from embedding AppleDouble ._ files when building Linux tarballs
COPYFILE_DISABLE=1 tar -czf release.tar.gz ./dist/
```

### Audit APFS Purgeable Space and Local Snapshots `[NON-ROOT]`

`df -h` hides APFS purgeable space (Time Machine local snapshots, OS update caches, iCloud evictable caches). Use `diskutil apfs list` or `tmutil` to see true reclaimable space.

```bash
diskutil apfs list | grep -E "Capacity|Snapshot|Purgeable"
tmutil listlocalsnapshotdates /
```

## High-Value defaults Tweaks

Apply targeted developer and admin ergonomics without breaking system stability.

`[NON-ROOT]`

```bash
# Show all filename extensions and hidden files in Finder
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

# Expand Save and Print panels by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

# Disable smart quotes/dashes (prevents mangled CLI flags in notes/editors)
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Save screenshots to a clean folder without drop shadows
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location -string "$HOME/Screenshots"
defaults write com.apple.screencapture disable-shadow -bool true

# Restart affected UI agents to apply immediately
killall Finder SystemUIServer
```

## Clipboard, Spotlight, and Metadata Quirks

### Pipe CLI Output Directly to Clipboard and Preview `[NON-ROOT]`

```bash
# Copy public SSH key to clipboard without trailing newline issues
tr -d '\n' < ~/.ssh/id_ed25519.pub | pbcopy

# Inspect clipboard contents in a pipeline
pbpaste | jq '.'

# Query Spotlight index from the terminal (faster than find for indexed volumes)
mdfind "kMDItemFSName == '*.plist' && kMDItemContentModificationDate >= \$time.today(-7)"
```

### Create a Service User Without a Login Shell or Home Directory `[ROOT]`

macOS does not ship `useradd`. Use `sysadminctl` for regular users or `dscl` for headless service accounts (UID range `200–499`).

```bash
# Find an unused UID in the system daemon range
dscl . -list /Users UniqueID | awk '$2 >= 200 && $2 < 500' | sort -k2 -n

# Create _exporter service user (example UID/GID 390)
sudo dscl . -create /Groups/_exporter PrimaryGroupID 390
sudo dscl . -create /Users/_exporter UniqueID 390
sudo dscl . -create /Users/_exporter PrimaryGroupID 390
sudo dscl . -create /Users/_exporter UserShell /usr/bin/false
sudo dscl . -create /Users/_exporter NFSHomeDirectory /var/empty
sudo dscl . -create /Users/_exporter RealName "Prometheus Node Exporter"
```

## Apple Silicon Telemetry Without Root Overhead

`powermetrics` requires `sudo` to sample SMC sensors, wattage, and GPU/ANE clocks. For continuous non-root monitoring, install `macmon` (reads IOReport channels directly).

`[NON-ROOT]`

```bash
brew install macmon
macmon

# One-shot root telemetry snapshot with built-in powermetrics
sudo powermetrics --samplers cpu_power,gpu_power,thermal -n 1 -i 1000
```
