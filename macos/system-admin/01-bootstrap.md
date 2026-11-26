# macOS System Administration Bootstrap

First-boot provisioning for macOS (Apple Silicon and Intel) covering Xcode Command Line Tools, Homebrew prefix alignment, shell PATH configuration, NTP time sync, `softwareupdate`, and baseline daemon hygiene.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Architecture and Prefix Verification](#architecture-and-prefix-verification)
- [Xcode Command Line Tools and Rosetta 2](#xcode-command-line-tools-and-rosetta-2)
- [Homebrew Installation and Shell Environment](#homebrew-installation-and-shell-environment)
- [Base Admin Packages and GNU Parity](#base-admin-packages-and-gnu-parity)
- [System Updates and Time Synchronization](#system-updates-and-time-synchronization)
- [Baseline Service and Power Verification](#baseline-service-and-power-verification)

## Architecture and Prefix Verification

Verify hardware architecture, macOS build, and APFS root layout before installing toolchains. Apple Silicon (`arm64`) and Intel (`x86_64`) use different Homebrew prefixes and binary paths.

`[NON-ROOT]`

```bash
uname -m
sw_vers
sysctl -n machdep.cpu.brand_string
diskutil apfs list
```

| Architecture | `uname -m` | Homebrew Prefix | Native Binary Path |
| :--- | :--- | :--- | :--- |
| Apple Silicon (M1–M4) | `arm64` | `/opt/homebrew` | `/opt/homebrew/bin` |
| Intel Mac | `x86_64` | `/usr/local` | `/usr/local/bin` |

> **Watch out:** Running a terminal under Rosetta 2 makes `uname -m` return `x86_64` on Apple Silicon, causing Homebrew and build scripts to target `/usr/local`. Verify native execution with `sysctl -n sysctl.proc_translated` (`0` means native, `1` means Rosetta).

## Xcode Command Line Tools and Rosetta 2

Install Apple's compilers (`clang`), `git`, `make`, and SDK headers without pulling the multi-gigabyte Xcode IDE.

### Interactive and Headless CLT Install `[ROOT]`

```bash
# Triggers GUI prompt on desktop sessions
xcode-select --install

# Headless / SSH-safe install via softwareupdate
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
CLT_PKG=$(softwareupdate -l | awk -F'* ' '/Command Line Tools/{print $2}' | sed 's/^Label: //' | sort -V | tail -n 1)
sudo softwareupdate -i "$CLT_PKG" --verbose
rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

# Confirm active developer directory
xcode-select -p
```

### Rosetta 2 for x86_64 Binaries on Apple Silicon `[ROOT]`

Only install Rosetta 2 if legacy `x86_64` CLIs or vendor agents require translation.

```bash
/usr/sbin/softwareupdate --install-rosetta --agree-to-license
```

## Homebrew Installation and Shell Environment

Install Homebrew as a standard administrator user (never as `root`) and wire its environment into both login (`~/.zprofile`) and non-interactive SSH shells.

`[NON-ROOT]`

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Configure Zsh Login Profile `[NON-ROOT]`

```bash
# Apple Silicon
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Intel Macs
# echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
# eval "$(/usr/local/bin/brew shellenv)"

brew doctor
```

> **Watch out:** Non-interactive SSH commands (`ssh host "brew --version"`) invoke `/bin/zsh` without reading `~/.zprofile`, so `/opt/homebrew/bin` is missing from `PATH`. Add `export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"` to `~/.zshenv` if automation tools (Ansible, GitHub Actions, SSH one-liners) invoke Homebrew binaries directly.

### Disable Analytics and Auto-Update Surprises `[NON-ROOT]`

```bash
brew analytics off
cat <<'EOF' >> ~/.zprofile
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_INSECURE_REDIRECT=1
export HOMEBREW_CASK_OPTS="--require-sha"
EOF
```

## Base Admin Packages and GNU Parity

macOS ships BSD userland utilities (`sed`, `grep`, `tar`, `find`, `date`) whose flags differ from GNU coreutils. Install core operational packages while keeping BSD binaries intact as defaults unless explicitly prefixed.

`[NON-ROOT]`

```bash
brew install \
  coreutils findutils gnu-sed gnu-tar grep gawk \
  jq yq ripgrep fd fzf tree tmux htop btop \
  mtr nmap iperf3 curl wget rsync watch \
  openssh openssl@3 gnupg
```

| macOS BSD Default | Homebrew GNU Binary | Key Behavioral Difference |
| :--- | :--- | :--- |
| `sed -i ''` | `gsed -i` | BSD `sed` requires an explicit backup suffix argument (`''`). |
| `date -r <epoch>` | `gdate -d @<epoch>` | BSD `date` rejects `-d` and `--iso-8601`. |
| `readlink` | `greadlink -f` | Older macOS lacks GNU `readlink -f` canonicalization. |
| `tar` (bsdtar) | `gtar` | macOS `tar` embeds `._*` AppleDouble metadata unless `COPYFILE_DISABLE=1`. |
| `rsync` (2.6.9 / openrsync) | `/opt/homebrew/bin/rsync` | Built-in `rsync` lacks `--info=progress2` and modern xattr/ACLs flags. |

> **Watch out:** Do not prepend `/opt/homebrew/opt/coreutils/libexec/gnubin` globally to `PATH` for system accounts or `root`. Apple scripts and third-party installers expect BSD `sed`, `stat`, and `xargs` semantics and will fail silently or corrupt files if shadowed by GNU variants.

## System Updates and Time Synchronization

### Configure NTP and Timezone `[ROOT]`

macOS uses `timed` for clock discipline. Verify UTC or local timezone alignment and confirm `systemsetup` NTP state.

```bash
sudo systemsetup -settimezone UTC
sudo systemsetup -setnetworktimeserver time.apple.com
sudo systemsetup -setusingnetworktime on

# Verify active time daemon status
sntp -sS time.apple.com
systemsetup -gettimezone
systemsetup -getnetworktimeserver
```

### Audit and Apply OS Updates `[ROOT]` `[REBOOT]`

```bash
# List available OS and security updates
softwareupdate --list

# Install all recommended updates and restart if required
sudo softwareupdate --install --recommended --restart

# Enable automatic security responses and system data files (XProtect, MRT)
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
```

## Baseline Service and Power Verification

Validate hostname identity, Spotlight indexing scope, and initial `launchd` and power settings immediately after provisioning.

`[ROOT]`

```bash
# Set consistent ComputerName, LocalHostName (Bonjour), and HostName (FQDN)
sudo scutil --set ComputerName "mac-node-01"
sudo scutil --set LocalHostName "mac-node-01"
sudo scutil --set HostName "mac-node-01.internal.lan"

# Inspect current power profile and active sleep assertions
pmset -g custom
pmset -g assertions

# Verify Spotlight indexing status across mounted volumes
mdutil -sa

# Check failed or crashed system launch daemons
sudo launchctl print system | grep -E "services =|last exit code" | head -n 40
```
