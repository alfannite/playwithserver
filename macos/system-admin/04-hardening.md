# macOS System Administration Hardening

Production-safe macOS security baseline covering account hygiene, sudo/Touch ID policies, launchd persistence auditing, TCC privacy boundaries, FileVault verification, and update integrity without breaking Homebrew, SSH, or containers.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Account Hygiene and Sudo Policy](#account-hygiene-and-sudo-policy)
- [System Integrity Protection and Sealed System Volume](#system-integrity-protection-and-sealed-system-volume)
- [Disk Encryption and Firmware Security](#disk-encryption-and-firmware-security)
- [Launchd Persistence and Login Item Auditing](#launchd-persistence-and-login-item-auditing)
- [Disable Unused Sharing and Discovery Services](#disable-unused-sharing-and-discovery-services)
- [Audit Logging and Security Updates](#audit-logging-and-security-updates)

## Account Hygiene and Sudo Policy

### Separate Admin and Daily Accounts `[ROOT]`

Keep `root` disabled (macOS default). Use `dscl` to confirm no unexpected users hold `admin` group membership or UID `0`.

```bash
# List members of the admin group
dscl . -read /Groups/admin GroupMembership

# Verify root account has no password enabled (AuthenticationAuthority should not exist or be disabled)
dscl . -read /Users/root AuthenticationAuthority 2>&1

# Disable Guest account and automatic GUI login
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
```

### Tighten Sudo Timeout and Preserve Safe Env `[ROOT]`

Always place custom sudo rules in `/etc/sudoers.d/` and validate with `visudo -c`.

```bash
sudo tee /etc/sudoers.d/10-admin-hardening >/dev/null <<'EOF'
Defaults timestamp_timeout=5
Defaults env_reset
Defaults tty_tickets
Defaults logfile="/var/log/sudo.log"
EOF
sudo chmod 440 /etc/sudoers.d/10-admin-hardening
sudo visudo -cf /etc/sudoers.d/10-admin-hardening
```

### Enable Touch ID for Local Sudo Safely `[ROOT]`

On macOS Sonoma (14+) and Sequoia (15+), use `/etc/pam.d/sudo_local` (persists across macOS upgrades, unlike `/etc/pam.d/sudo`).

```bash
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
```

> **Watch out:** Never edit `/etc/pam.d/sudo` directly; macOS point updates overwrite it cleanly. Also do not enable `pam_tid.so` without confirming password fallback works over SSH—`pam_tid.so` automatically skips Touch ID when no local console session exists, falling back cleanly to `pam_opendirectory.so`.

## System Integrity Protection and Sealed System Volume

Verify that Apple's core OS integrity layers remain intact. Never disable SIP in production.

`[NON-ROOT]`

```bash
# Confirm SIP is enabled
csrutil status

# Confirm Signed System Volume (SSV) sealing is intact
csrutil authenticated-root status

# Confirm Gatekeeper and XProtect definitions are active
spctl --status
system_profiler SPInstallHistoryDataType | grep -A 3 "XProtect" | tail -n 12
```

| Security Layer | Expected State | What Breaks If Disabled |
| :--- | :--- | :--- |
| SIP (`csrutil status`) | `enabled` | Kernel extensions and `/System` become writable; Apple Pay and some MDM policies fail |
| SSV (`authenticated-root`) | `enabled` | Boot snapshot cryptographic verification is bypassed |
| Gatekeeper (`spctl --status`) | `assessments enabled` | Unsigned/unnotarized binaries execute without quarantine verification |

## Disk Encryption and Firmware Security

### Verify FileVault and Recovery Key Escrow `[ROOT]`

```bash
# Confirm FileVault encryption status and authorized unlock users
fdesetup status
sudo fdesetup list

# Verify whether a personal recovery key is set
sudo fdesetup haspersonalrecoverykey
```

> **Watch out:** Enabling FileVault on a headless Mac without planning for reboots locks the machine at the pre-boot unlock screen where SSH and `launchd` are not yet running. For unattended servers, review the reboot strategy in `macos/mac-as-server/04-hardening.md` (`fdesetup authrestart` or split encrypted APFS data volume).

### Apple Silicon Startup Security Check `[NON-ROOT]`

```bash
# Inspect boot security policy (Full Security is default on Apple Silicon)
bputil -d 2>/dev/null || system_profiler SPiBridgeDataType
```

## Launchd Persistence and Login Item Auditing

Audit all persistence locations regularly to detect unauthorized agents, vendor updaters, or legacy kernel extensions.

`[NON-ROOT]` / `[ROOT]`

```bash
# List all third-party daemons and agents
ls -la /Library/LaunchDaemons /Library/LaunchAgents ~/Library/LaunchAgents

# Inspect background items managed by Service Management (macOS 13+)
sudo sfltool dumpbtm | grep -E "Name:|URL:|Disposition:|Developer Name:" | head -n 60

# Verify code signatures on all third-party LaunchDaemon executables
for plist in /Library/LaunchDaemons/*.plist; do
  bin=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null)
  [ -n "$bin" ] && echo "=== $plist -> $bin ===" && codesign -dvv "$bin" 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
done
```

### Restrict Cron and At Usage `[ROOT]`

Allow `cron` only for explicitly listed accounts (or restrict completely in favor of `launchd` `StartCalendarInterval`).

```bash
echo "root" | sudo tee /var/at/cron.allow >/dev/null
sudo chmod 600 /var/at/cron.allow
```

## Disable Unused Sharing and Discovery Services

Turn off desktop sharing daemons not explicitly required by the host's role. Keep SSH (`Remote Login`) controlled separately with key-only authentication.

`[ROOT]`

```bash
# Disable SMB File Sharing unless actively serving shares
sudo launchctl disable system/com.apple.smbd
sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.smbd.plist 2>/dev/null || true

# Disable AirDrop and AirPlay Receiver on server/workstation baselines
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
defaults write com.apple.controlcenter AirplayRecieverEnabled -bool false

# Disable Wake for Network Access only on untrusted portable laptops (leave ON for headless servers)
# sudo pmset -a womp 0

# Disable remote Apple Events
sudo systemsetup -setremoteappleevents off
```

## Audit Logging and Security Updates

### Enable OpenBSM Security Auditing (Where Supported) `[ROOT]`

```bash
# Check if auditd is active (macOS marks auditd deprecated in favor of Endpoint Security, but it still functions on many builds)
sudo launchctl print system/com.apple.auditd 2>&1 | head -n 15

# Ensure sudo and unified logs retain critical auth events
log show --last 24h --predicate 'process == "sudo" OR process == "sshd"' --style compact | tail -n 20
```

### Lock In Automatic Background Security Patches `[ROOT]`

```bash
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
```

### Verify Permissions on Homebrew Prefix `[NON-ROOT]`

Ensure `/opt/homebrew` is not world-writable so unprivileged processes cannot hijack binaries in `PATH`.

```bash
find /opt/homebrew -maxdepth 2 -perm -0002 -ls
```
