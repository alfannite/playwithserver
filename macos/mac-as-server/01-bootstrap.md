# Headless Mac Server Bootstrap

First-boot provisioning for a 24/7 headless Mac Mini (Apple Silicon M1–M4 or Intel) covering always-on power policy, SSH Remote Login, Screen Sharing/ARD, HDMI dummy plug setup, Homebrew `Brewfile` reproducibility, and container/VM runtime initialization.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Hardware Prerequisites for Headless Operation](#hardware-prerequisites-for-headless-operation)
- [Always-On Power Management Policy](#always-on-power-management-policy)
- [Enable SSH Remote Login and Access Control](#enable-ssh-remote-login-and-access-control)
- [Enable Screen Sharing and ARD Safely](#enable-screen-sharing-and-ard-safely)
- [Reproducible Provisioning with Homebrew Brewfile](#reproducible-provisioning-with-homebrew-brewfile)
- [Network Identity, Tailscale, and Container Runtime](#network-identity-tailscale-and-container-runtime)

## Hardware Prerequisites for Headless Operation

Before moving a Mac Mini into a rack or closet, address two physical constraints:

1. **HDMI/DisplayPort EDID Dummy Plug:** Without an attached display (or virtual display), macOS disables hardware GPU acceleration for WindowServer, causing Screen Sharing to fall back to sluggish software rendering, low fixed resolutions, and stalled GUI automation. Plugging a 4K/1080p HDMI EDID emulator (~$5) into the HDMI port keeps Metal acceleration and HiDPI Screen Sharing active at zero monitor power draw.
2. **Wired Ethernet + UPS:** Connect over gigabit/10GbE Ethernet and configure a static IP or DHCP reservation. Put the Mac Mini on a USB-monitored UPS so macOS executes a clean shutdown before battery exhaustion.

> **Watch out:** On macOS Sequoia (15+) and Sonoma (14+), Apple requires enabling Remote Login or granting Full Disk Access to Terminal locally during initial setup if you plan to configure `systemsetup -setremotelogin on` from a script. Complete the initial Setup Assistant locally (or via temporary monitor) before moving the node headless.

## Always-On Power Management Policy

Disable all sleep states, enable Wake-on-LAN (`womp`), and force automatic reboot after power loss (`autorestart 1`).

`[ROOT]`

```bash
sudo pmset -a \
  autorestart 1 \
  womp 1 \
  sleep 0 \
  displaysleep 0 \
  disksleep 0 \
  powernap 0 \
  standby 0 \
  autopoweroff 0 \
  hibernatemode 0 \
  tcpkeepalive 1

# Verify applied profile
pmset -g custom
```

| `pmset` Key | Value | Purpose on 24/7 Headless Mac |
| :--- | :--- | :--- |
| `autorestart` | `1` | Automatically powers on after AC power outage recovery |
| `womp` | `1` | Enables Wake-on-LAN magic packet wake |
| `sleep` | `0` | Prevents system idle sleep |
| `displaysleep` | `0` | Keeps virtual/dummy display awake for instant Screen Sharing |
| `disksleep` | `0` | Prevents external Thunderbolt/USB4 NVMe enclosures from spinning down or disconnecting |
| `powernap` | `0` | Disables unpredictable dark-wake cycles |

### Enable Automatic macOS Crash Recovery `[ROOT]`

```bash
# Automatically restart if the macOS kernel or WindowServer freezes
sudo systemsetup -setrestartfreeze on
sudo systemsetup -setrestartpowerfailure on
```

## Enable SSH Remote Login and Access Control

Enable Apple's built-in OpenSSH daemon (`com.openssh.sshd`) and restrict access to a dedicated `ssh` access group.

`[ROOT]`

```bash
# Turn on Remote Login (requires Full Disk Access if run from Terminal on macOS 13+)
sudo systemsetup -setremotelogin on
sudo systemsetup -getremotelogin

# Confirm sshd is listening on port 22
sudo lsof -nP -iTCP:22 -sTCP:LISTEN
```

Install your SSH public key from your admin workstation:

`[NON-ROOT]`

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub admin@mac-mini.lan
```

## Enable Screen Sharing and ARD Safely

Enable Apple Remote Desktop / Screen Sharing (`RFB` port 5900) for occasional GUI tasks (OS upgrades, system extension approvals, UTM console), then restrict access strictly to SSH tunnels or Tailscale rather than exposing port 5900 to the LAN.

`[ROOT]`

```bash
KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"

# Activate Remote Management and grant access strictly to the 'admin' user
sudo "$KICKSTART" -activate -configure -access -on \
  -users admin -privs -all \
  -allowAccessFor -specifiedUsers \
  -restart -agent -menu
```

Connect securely over an SSH local port forward without exposing VNC (`5900`) on the LAN:

`[NON-ROOT]`

```bash
# Run on your workstation, then open vnc://127.0.0.1:15900 in Finder / Screen Sharing.app
ssh -N -L 15900:127.0.0.1:5900 admin@mac-mini.lan
```

> **Watch out:** On macOS 12.1+, `kickstart` can configure ARD permissions and restart the agent, but Apple blocks enabling Screen Sharing *from scratch* solely via SSH for security reasons unless a local user (or MDM profile) has previously enabled Screen Sharing / Remote Management in System Settings -> General -> Sharing.

## Reproducible Provisioning with Homebrew Brewfile

Maintain the entire server package set declaratively in a Git-tracked `Brewfile` so rebuilding a Mac Mini takes one command.

`[NON-ROOT]`

```bash
# Export currently installed formulae, casks, and taps to ~/Brewfile
brew bundle dump --describe --force --file=~/Brewfile

# Apply a Brewfile on a freshly provisioned Mac Mini
brew bundle install --file=~/Brewfile

# Verify drift between installed packages and Brewfile
brew bundle check --file=~/Brewfile
```

### Example Minimal Server `Brewfile`

```ruby
tap "homebrew/bundle"

brew "coreutils"
brew "tmux"
brew "htop"
brew "btop"
brew "jq"
brew "yq"
brew "ripgrep"
brew "rsync"
brew "mtr"
brew "iperf3"
brew "tailscale"
brew "colima"
brew "docker"
brew "docker-compose"
brew "lima"
brew "cirruslabs/cli/tart"

cask "orbstack"
cask "utm"
```

## Network Identity, Tailscale, and Container Runtime

### Set Hostnames and Install Headless Tailscale Daemon `[ROOT]`

For a 24/7 server, prefer the Homebrew `tailscaled` system daemon (or macOS standalone package) over the Mac App Store GUI app, which only starts after a GUI login.

```bash
sudo scutil --set ComputerName "mac-srv-01"
sudo scutil --set LocalHostName "mac-srv-01"
sudo scutil --set HostName "mac-srv-01.internal.lan"

# Start Tailscale as a root LaunchDaemon so VPN comes up BEFORE GUI login
brew install tailscale
sudo brew services start tailscale
sudo tailscale up --ssh=false --accept-dns=false
```

### Enable Container Runtime (OrbStack or Colima) `[NON-ROOT]`

```bash
# Option A: OrbStack (fast Apple Virtualization Framework runtime, GUI + CLI)
brew install --cask orbstack
open -a OrbStack
orb config set memory_mib 8192
orb config set cpu 4

# Option B: Colima (100% open-source CLI runtime via Lima + Apple VZ)
brew install colima docker docker-compose
colima start --cpu 4 --memory 8 --disk 80 --vm-type vz --vz-rosetta --mount-type virtiofs
```
