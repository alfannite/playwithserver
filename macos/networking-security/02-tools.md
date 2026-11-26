# macOS Networking and Security Tools

Production CLI reference for `pfctl`, `scutil`, `networksetup`, `lsof`, `nettop`, `socketfilterfw`, `codesign`/`spctl`/`xattr`, `fdesetup`, and macOS egress firewalls.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Tools Quick Matrix](#tools-quick-matrix)
- [pfctl (Packet Filter Firewall and NAT)](#pfctl-packet-filter-firewall-and-nat)
- [scutil (SystemConfiguration DNS, Proxy, and Hostname)](#scutil-systemconfiguration-dns-proxy-and-hostname)
- [networksetup (Interfaces, VLANs, DNS, and Locations)](#networksetup-interfaces-vlans-dns-and-locations)
- [lsof and nettop (Socket and Per-Process Traffic Inspection)](#lsof-and-nettop-socket-and-per-process-traffic-inspection)
- [socketfilterfw (Application Firewall)](#socketfilterfw-application-firewall)
- [spctl, codesign, and xattr (Gatekeeper and Quarantine)](#spctl-codesign-and-xattr-gatekeeper-and-quarantine)
- [fdesetup and csrutil (FileVault and SIP)](#fdesetup-and-csrutil-filevault-and-sip)
- [LuLu and Little Snitch (Egress Firewalls)](#lulu-and-little-snitch-egress-firewalls)

## Tools Quick Matrix

| Tool | Source | Domain | Primary Use Case |
| :--- | :--- | :--- | :--- |
| `pfctl` | Built-in (`/sbin/pfctl`) | L3/L4 Firewall / NAT | Dry-run, load, and inspect OpenBSD-derived Packet Filter rules & anchors |
| `scutil` | Built-in (`/usr/sbin/scutil`) | SystemConfiguration | Inspect live DNS, network reachability, proxies, and set hostnames |
| `networksetup` | Built-in (`/usr/sbin/networksetup`) | Network Config | Manage interfaces, static IPs, DNS, VLANs, proxies, and locations |
| `lsof` | Built-in (`/usr/sbin/lsof`) | Socket Audit | List open TCP/UDP sockets and owning PIDs (macOS replacement for `ss`) |
| `nettop` | Built-in (`/usr/bin/nettop`) | Live Bandwidth | Real-time per-process socket throughput and state monitor |
| `socketfilterfw` | Built-in (`/usr/libexec/ApplicationFirewall/`) | App Firewall | Control macOS Application Firewall global state, stealth mode, and app rules |
| `spctl` / `codesign` / `xattr` | Built-in (`/usr/sbin/spctl`, `/usr/bin/`) | Code Trust | Audit Gatekeeper assessments, code signatures, and quarantine flags |
| `fdesetup` | Built-in (`/usr/bin/fdesetup`) | Disk Encryption | Check FileVault status, manage unlock users, execute `authrestart` |
| `csrutil` | Built-in (`/usr/bin/csrutil`) | Kernel Integrity | Inspect System Integrity Protection (SIP) and SSV status |
| `LuLu` / `Little Snitch` | `brew install --cask lulu` / Commercial | Egress Control | Inspect and block unauthorized outbound connections by process |

## pfctl (Packet Filter Firewall and NAT)

**Install:** Built-in (`/sbin/pfctl`).

### High-Signal Usages `[ROOT]`

```bash
# Dry-run parse and expand macros/tables without loading rules
sudo pfctl -vnf /etc/pf.local.conf

# Load ruleset and enable Packet Filter (-e enable, -f file)
sudo pfctl -ef /etc/pf.local.conf

# Inspect active filter rules (-sr), NAT/redirect rules (-sn), or all info/states (-sa)
sudo pfctl -sr
sudo pfctl -sn
sudo pfctl -sa | head -n 60

# Inspect rules inside a specific custom anchor
sudo pfctl -a com.local.custom -sr

# Flush and disable PF cleanly in an emergency
sudo pfctl -d
```

> **Watch out:** macOS `pfctl -e` increments a reference token (`-E` creates a token, `-X <token>` releases it). System services like AirDrop, Internet Sharing, and Adaptive Firewall also take PF references. Running `pfctl -f /etc/pf.local.conf` without preserving `anchor "com.apple/*"` breaks macOS Internet Sharing, VM bridges, and Continuity features.

## scutil (SystemConfiguration DNS, Proxy, and Hostname)

**Install:** Built-in (`/usr/sbin/scutil`).

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Display the exact scoped and split-DNS resolver table used by mDNSResponder
scutil --dns

# Show active network interface state, reachability flags, and IPv4/IPv6 routes
scutil --nwi

# Display active system HTTP/HTTPS/SOCKS/PAC proxy configuration
scutil --proxy

# Read or set the three macOS hostname attributes
scutil --get HostName
sudo scutil --set HostName "mac-edge-01.internal.lan"
sudo scutil --set LocalHostName "mac-edge-01"
sudo scutil --set ComputerName "mac-edge-01"
```

> **Watch out:** `dig` and `nslookup` read `/etc/resolv.conf` directly and completely bypass macOS's `mDNSResponder` split-DNS rules (`scutil --dns` scoped resolvers and `/etc/resolver/*`). Always validate real macOS application DNS resolution with `dscacheutil -q host -a name <fqdn>` alongside `scutil --dns`.

## networksetup (Interfaces, VLANs, DNS, and Locations)

**Install:** Built-in (`/usr/sbin/networksetup`).

### High-Signal Usages `[ROOT]`

```bash
# List hardware ports and service names
networksetup -listallhardwareports
networksetup -listallnetworkservices

# Configure DNS servers (use "Empty" to revert to DHCP-supplied DNS)
sudo networksetup -setdnsservers "Ethernet" 1.1.1.1 9.9.9.9
sudo networksetup -setdnsservers "Ethernet" Empty

# Create a tagged 802.1Q VLAN interface on en0 (VLAN ID 20)
sudo networksetup -createVLAN "Server-VLAN20" en0 20
networksetup -listVLANs

# Configure or disable a SOCKS proxy on a specific service
sudo networksetup -setsocksfirewallproxy "Wi-Fi" 127.0.0.1 1080
sudo networksetup -setsocksfirewallproxystate "Wi-Fi" off

# Switch network Locations (e.g., Lab vs Automatic)
networksetup -listlocations
sudo networksetup -switchtolocation "Automatic"
```

> **Watch out:** `networksetup -setdnsservers` overwrites the entire DNS list for that service rather than appending. Always pass all desired resolvers in one command, and quote service names containing spaces (e.g., `"USB 10/100/1000 LAN"`).

## lsof and nettop (Socket and Per-Process Traffic Inspection)

**Install:** Built-in (`/usr/sbin/lsof`, `/usr/bin/nettop`). macOS does not ship Linux `ss`; `lsof` and `nettop` are the authoritative replacements.

### High-Signal Usages `[ROOT]` / `[NON-ROOT]`

```bash
# List all listening TCP sockets with numeric ports and owning PIDs
sudo lsof -nP -iTCP -sTCP:LISTEN

# List all listening UDP sockets and active established connections
sudo lsof -nP -iUDP
sudo lsof -nP -iTCP -sTCP:ESTABLISHED

# Inspect which process owns a specific port (e.g., 8080)
sudo lsof -nP -i :8080

# Non-interactive single snapshot of per-process network bytes in/out (-P collapses per-process, -L 1 one sample)
nettop -P -L 1 -J bytes_in,bytes_out -t external
```

> **Watch out:** Running `lsof` without `sudo` only displays sockets owned by your current UID, silently hiding root daemons (`sshd`, `mDNSResponder`, container runtimes) listening on privileged ports. Always include `-nP` to disable slow reverse DNS and port-name resolution.

## socketfilterfw (Application Firewall)

**Install:** Built-in (`/usr/libexec/ApplicationFirewall/socketfilterfw`).

### High-Signal Usages `[ROOT]`

```bash
SFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

# Enable firewall and stealth mode (drops unsolicited ICMP ping and closed-port probes)
sudo "$SFW" --setglobalstate on
sudo "$SFW" --setstealthmode on

# Explicitly allow or block a specific binary path
sudo "$SFW" --add /opt/homebrew/bin/caddy
sudo "$SFW" --unblockapp /opt/homebrew/bin/caddy
sudo "$SFW" --blockapp /Applications/Example.app

# Inspect all application firewall rules
sudo "$SFW" --listapps
```

> **Watch out:** `socketfilterfw` operates at the application binary level and evaluates processes by code signature. Unsigned Homebrew binaries rebuilt via `brew upgrade` change their binary hash/ad-hoc signature, which can cause `socketfilterfw` to silently re-block incoming connections until `--unblockapp` is re-run or the binary is signed.

## spctl, codesign, and xattr (Gatekeeper and Quarantine)

**Install:** Built-in (`/usr/sbin/spctl`, `/usr/bin/codesign`, `/usr/bin/xattr`).

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Verify whether Gatekeeper accepts an app or CLI binary
spctl --assess --type execute --verbose=4 /Applications/OrbStack.app

# Inspect cryptographic signing authority, Team ID, and entitlements
codesign -dv --verbose=4 /usr/sbin/sshd
codesign --verify --deep --strict /Applications/OrbStack.app

# Inspect extended attributes (including com.apple.quarantine) on downloaded files
xattr -lr ~/Downloads/tool-binary

# Remove quarantine flag ONLY after verifying SHA256 checksum of a trusted binary
xattr -dr com.apple.quarantine /Applications/TrustedTool.app
```

> **Watch out:** Never disable Gatekeeper globally (`spctl --master-disable`) just to run one unsigned internal CLI. Verify the binary's SHA256 checksum first, then remove `com.apple.quarantine` selectively on that single binary (`xattr -d com.apple.quarantine <path>`).

## fdesetup and csrutil (FileVault and SIP)

**Install:** Built-in (`/usr/bin/fdesetup`, `/usr/bin/csrutil`).

### High-Signal Usages `[ROOT]`

```bash
# Check FileVault encryption state and authorized pre-boot users
fdesetup status
sudo fdesetup list

# Perform a single authenticated reboot that bypasses the FileVault pre-boot lock screen
sudo fdesetup authrestart

# Verify SIP and Signed System Volume sealing
csrutil status
csrutil authenticated-root status
```

> **Watch out:** `fdesetup authrestart` only bypasses the FileVault pre-boot prompt for a *single* planned reboot and requires entering a Volume Owner password interactively (or via plist). It does not survive an unexpected power loss.

## LuLu and Little Snitch (Egress Firewalls)

**Install:**
- **LuLu (free, open-source):** `brew install --cask lulu`
- **Little Snitch (commercial, includes CLI `littlesnitch`):** `brew install --cask little-snitch`

### High-Signal Usages `[NON-ROOT]` / `[ROOT]`

```bash
# Verify Objective-See LuLu system network extension is loaded and active
systemextensionsctl list | grep -i lulu

# Little Snitch CLI (when installed): export rules and inspect live connection traffic
littlesnitch export-model > ~/littlesnitch-backup.json
littlesnitch log --last 10m
```

> **Watch out:** macOS network extensions (LuLu, Little Snitch, Tailscale, WireGuard, CrowdStrike) require interactive user approval in System Settings -> Privacy & Security (or an MDM `SystemExtensions` profile) on initial install. Installing them blindly over SSH on a headless Mac leaves the filter inactive until approved locally or via Screen Sharing.
