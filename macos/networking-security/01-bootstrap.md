# macOS Networking and Security Bootstrap

Initial network interface configuration, DNS resolver setup, Application Firewall activation, Packet Filter (`pf`) anchor scaffolding, and baseline security posture verification on macOS.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Identify Network Services and Interfaces](#identify-network-services-and-interfaces)
- [Configure Static IP, DNS, and Hostnames](#configure-static-ip-dns-and-hostnames)
- [Enable macOS Application Firewall](#enable-macos-application-firewall)
- [Scaffold Custom Packet Filter Anchors](#scaffold-custom-packet-filter-anchors)
- [Verify SIP, Gatekeeper, and FileVault Baseline](#verify-sip-gatekeeper-and-filevault-baseline)
- [Install Core Network Inspection Utilities](#install-core-network-inspection-utilities)

## Identify Network Services and Interfaces

macOS distinguishes BSD kernel interfaces (`en0`, `en1`, `utun3`) from high-level SystemConfiguration network service names (`Ethernet`, `Wi-Fi`, `Thunderbolt Bridge`). `networksetup` requires the service name; `pfctl` and `ifconfig` require the BSD interface name.

`[NON-ROOT]`

```bash
# Map hardware ports to BSD device identifiers
networksetup -listallhardwareports

# List network services in active priority order
networksetup -listnetworkserviceorder

# Inspect active IPv4/IPv6 network reachability and default routes
scutil --nwi
route -n get default
```

## Configure Static IP, DNS, and Hostnames

### Set Host Identity Consistently `[ROOT]`

macOS maintains three independent hostname fields. Aligning them prevents Bonjour (`.local`), SSH, and TLS certificate mismatches.

```bash
sudo scutil --set ComputerName "mac-edge-01"
sudo scutil --set LocalHostName "mac-edge-01"
sudo scutil --set HostName "mac-edge-01.internal.lan"
```

### Assign Static IPv4 and Custom DNS via `networksetup` `[ROOT]`

Replace `"Ethernet"` with the exact service name reported by `networksetup -listallnetworkservices`.

```bash
# Configure manual IPv4 address, subnet mask, and gateway
sudo networksetup -setmanual "Ethernet" 192.168.10.50 255.255.255.0 192.168.10.1

# Set explicit DNS resolvers and search domains
sudo networksetup -setdnsservers "Ethernet" 192.168.10.1 1.1.1.1
sudo networksetup -setsearchdomains "Ethernet" internal.lan

# Confirm active resolver state via SystemConfiguration (never rely solely on /etc/resolv.conf)
scutil --dns | head -n 45
```

> **Watch out:** macOS ignores `/etc/resolv.conf` for native `mDNSResponder` lookups and overwrites it dynamically from `configd`. Always inspect DNS with `scutil --dns` and configure resolvers via `networksetup` or `/etc/resolver/<domain>` split-DNS files.

## Enable macOS Application Firewall

Activate Apple's built-in Application Layer Firewall (`socketfilterfw`) in non-disruptive mode before deploying custom Packet Filter (`pf`) rules.

`[ROOT]`

```bash
SFW="/usr/libexec/ApplicationFirewall/socketfilterfw"

sudo "$SFW" --setglobalstate on
sudo "$SFW" --setloggingmode on
sudo "$SFW" --setstealthmode on

# Allow signed built-in and downloaded apps automatically to avoid breaking SSH/Docker/Homebrew initially
sudo "$SFW" --setallowsigned on
sudo "$SFW" --setallowsignedapp on

# Inspect active status and rules
sudo "$SFW" --getglobalstate
sudo "$SFW" --listapps
```

## Scaffold Custom Packet Filter Anchors

macOS ships with `/etc/pf.conf` managed by Apple and disabled by default (`pfctl -s info`). Never overwrite Apple's default anchor (`com.apple/*`) directly; attach a dedicated custom anchor file in `/etc/pf.anchors/`.

`[ROOT]`

```bash
# Create a custom anchor file for host rules
sudo tee /etc/pf.anchors/com.local.custom >/dev/null <<'EOF'
# Custom host firewall rules loaded via /etc/pf.local.conf
set block-policy return
set skip on lo0

# Allow established outbound state and essential ICMP
pass out quick inet proto { tcp, udp, icmp } keep state
pass in inet proto icmp all icmp-type echoreq keep state

# Allow SSH on LAN subnet (adjust CIDR before enabling default-deny)
pass in quick proto tcp from 192.168.10.0/24 to any port 22 keep state
EOF

# Create a wrapper config that preserves Apple's default rules plus your custom anchor
sudo tee /etc/pf.local.conf >/dev/null <<'EOF'
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"

anchor "com.local.custom"
load anchor "com.local.custom" from "/etc/pf.anchors/com.local.custom"
EOF

# Dry-run syntax check without modifying the running packet filter
sudo pfctl -vnf /etc/pf.local.conf
```

> **Watch out:** Editing `/etc/pf.conf` directly is reverted by macOS upgrades. Keep custom rules in `/etc/pf.local.conf` and `/etc/pf.anchors/com.local.*`, and load `/etc/pf.local.conf` from a dedicated LaunchDaemon on boot. Always test with `pfctl -vnf` before applying live.

## Verify SIP, Gatekeeper, and FileVault Baseline

Capture the baseline cryptographic and OS integrity state right after setup.

`[NON-ROOT]` / `[ROOT]`

```bash
csrutil status
spctl --status
fdesetup status
sudo lsof -nP -iTCP -sTCP:LISTEN
```

| Check | Expected Output | Notes |
| :--- | :--- | :--- |
| `csrutil status` | `System Integrity Protection status: enabled.` | Required for kernel/system volume integrity |
| `spctl --status` | `assessments enabled` | Enforces notarization and quarantine checks |
| `fdesetup status` | `FileVault is On.` | Plan pre-boot unlock if headless |
| `lsof -nP -iTCP -sTCP:LISTEN` | Only expected daemons (`sshd`, etc.) | Baseline before exposing host to LAN/VPN |

## Install Core Network Inspection Utilities

Complement built-in Darwin tools (`pfctl`, `scutil`, `networksetup`, `lsof`, `nettop`, `tcpdump`) with Homebrew CLI diagnostics and optional open-source egress control.

`[NON-ROOT]`

```bash
brew install mtr nmap iperf3 bind ngrep socat bandwhich
# Optional open-source GUI egress firewall (Objective-See LuLu)
brew install --cask lulu
```
