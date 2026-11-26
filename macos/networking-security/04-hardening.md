# macOS Networking and Security Hardening

Production-safe network and OS security baseline using `pf` anchors, `socketfilterfw`, hardened `sshd_config.d`, kernel sysctl protections, and TLS/code-signing verification without breaking SSH, Tailscale, OrbStack, or Colima.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Hardened OpenSSH Server Configuration](#hardened-openssh-server-configuration)
- [Production-Safe Packet Filter Ruleset](#production-safe-packet-filter-ruleset)
- [Persist Packet Filter Across Reboots](#persist-packet-filter-across-reboots)
- [Application Firewall and Stealth Mode](#application-firewall-and-stealth-mode)
- [Network Kernel Parameters and IPv6/mDNS Controls](#network-kernel-parameters-and-ipv6mdns-controls)
- [Verify Listening Attack Surface and Active Extensions](#verify-listening-attack-surface-and-active-extensions)

## Hardened OpenSSH Server Configuration

macOS supports drop-in snippets in `/etc/ssh/sshd_config.d/`. Never edit `/etc/ssh/sshd_config` directly because macOS updates overwrite it.

`[ROOT]`

```bash
# Ensure your SSH public key is installed and verified BEFORE disabling passwords
ls -la ~/.ssh/authorized_keys

sudo tee /etc/ssh/sshd_config.d/10-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers admin
EOF

# Validate syntax before restarting sshd
sudo sshd -t

# Restart SSH safely (existing SSH session stays alive; test a NEW session before disconnecting)
sudo launchctl kickstart -k system/com.openssh.sshd
```

> **Watch out:** macOS ships `/etc/ssh/sshd_config.d/100-macos.conf` by default, which may re-enable `KbdInteractiveAuthentication` or `UsePAM`. OpenSSH uses **first-match-wins** semantics, so naming your drop-in `10-hardening.conf` guarantees it takes precedence over `100-macos.conf`. Verify effective settings with `sudo sshd -T | grep -E "passwordauthentication|kbdinteractive|permitrootlogin"`.

## Production-Safe Packet Filter Ruleset

This baseline blocks unsolicited inbound connections on physical interfaces while preserving outbound state, loopback, container/VM virtual bridges (`bridge*`, `vmenet*`), and VPN tunnels (`utun*`).

### Create `/etc/pf.anchors/com.local.hardening` `[ROOT]`

```text
# Interfaces and trusted admin networks
ext_if = "en0"
admin_nets = "{ 192.168.10.0/24, 100.64.0.0/10 }"

set block-policy drop
set skip on lo0

# Do not disrupt container/VM virtual switches or VPN tunnels (Tailscale/WireGuard)
set skip on { utun0, utun1, utun2, utun3, utun4, bridge100 }

# Anti-spoofing and normalization
scrub in all fragment reassemble

# Default inbound deny on physical NIC, allow all stateful outbound
block in log on $ext_if all
pass out on $ext_if all keep state

# Rate-limited SSH exclusively from trusted LAN / Tailscale CGNAT
table <ssh_abuse> persist
block drop in quick from <ssh_abuse>
pass in quick on $ext_if proto tcp from $admin_nets to ($ext_if) port 22 \
  flags S/SA keep state (max-src-conn 10, max-src-conn-rate 6/60, overload <ssh_abuse> flush global)

# Allow Tailscale WireGuard UDP direct path (41641) and ICMPv4/v6 diagnostics from admin nets
pass in quick on $ext_if proto udp to ($ext_if) port 41641 keep state
pass in quick on $ext_if inet proto icmp from $admin_nets to ($ext_if) icmp-type echoreq keep state
pass in quick on $ext_if inet6 proto icmp6 all icmp6-type { neighbrsol, neighbradv, routersol, routeradv } keep state
```

### Safe Rollout with Automatic Dead-Man's Rollback `[ROOT]`

Prevent remote SSH lockout by scheduling an automatic `pfctl -d` rollback 90 seconds after testing, then cancelling it once a new SSH session succeeds.

```bash
sudo pfctl -vnf /etc/pf.local.conf

# Load PF with a 90-second safety rollback in the background
sudo sh -c 'pfctl -ef /etc/pf.local.conf && (sleep 90 && pfctl -d) &'
# Open a second SSH terminal to verify access; if successful, cancel the rollback:
# sudo pkill -f "sleep 90"
```

> **Watch out:** OrbStack, Colima, Lima, and UTM allocate virtual bridge interfaces (`bridge100`, `bridge101`) and `utun*` devices dynamically. Never use a blanket `block in all` across *all* interfaces without explicitly scoping rules to the physical NIC (`on $ext_if`) or skipping container/VPN interfaces, or inter-container DNS and host-to-VM routing will break silently.

## Persist Packet Filter Across Reboots

macOS enables `com.apple.pfctl` at boot only if configured, and loads `/etc/pf.conf` by default. Create a dedicated LaunchDaemon to load `/etc/pf.local.conf` reliably.

`[ROOT]`

```bash
sudo tee /Library/LaunchDaemons/com.local.pf.plist >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.pf</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/pfctl</string>
    <string>-ef</string>
    <string>/etc/pf.local.conf</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/var/log/pf-local.err.log</string>
</dict>
</plist>
EOF

sudo chown root:wheel /Library/LaunchDaemons/com.local.pf.plist
sudo chmod 644 /Library/LaunchDaemons/com.local.pf.plist
plutil -lint /Library/LaunchDaemons/com.local.pf.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.pf.plist
```

## Application Firewall and Stealth Mode

Layer `socketfilterfw` alongside `pf` for binary-level inbound visibility.

`[ROOT]`

```bash
SFW="/usr/libexec/ApplicationFirewall/socketfilterfw"
sudo "$SFW" --setglobalstate on
sudo "$SFW" --setstealthmode on
sudo "$SFW" --setloggingmode on
sudo "$SFW" --setallowsigned on
sudo "$SFW" --setallowsignedapp off
```

Note: Setting `--setallowsignedapp off` stops third-party downloaded apps from auto-opening inbound ports without explicit approval via `--add` / `--unblockapp`, while `--setallowsigned on` keeps Apple system daemons (`sshd`, `mDNSResponder`) functional.

## Network Kernel Parameters and IPv6/mDNS Controls

Harden BSD TCP/IP stack parameters against ICMP redirects and source-routed packets without breaking container NAT or IPv6 Neighbor Discovery.

`[ROOT]`

```bash
# Apply immediately (non-persistent; wrap in a LaunchDaemon or /etc/sysctl.conf to persist)
sudo sysctl -w net.inet.icmp.drop_redirect=1
sudo sysctl -w net.inet.ip.redirect=0
sudo sysctl -w net.inet.ip.sourceroute=0
sudo sysctl -w net.inet.ip.accept_sourceroute=0
sudo sysctl -w net.inet.tcp.blackhole=2
sudo sysctl -w net.inet.udp.blackhole=1
```

| Sysctl Key | Value | Effect |
| :--- | :--- | :--- |
| `net.inet.icmp.drop_redirect` | `1` | Ignore hostile ICMP route redirects |
| `net.inet.ip.redirect` | `0` | Prevent host from emitting ICMP redirects |
| `net.inet.ip.sourceroute` | `0` | Disable IPv4 source routing |
| `net.inet.tcp.blackhole` | `2` | Drop TCP packets to closed ports silently (no RST) |
| `net.inet.udp.blackhole` | `1` | Drop UDP packets to closed ports silently (no ICMP unreachable) |

## Verify Listening Attack Surface and Active Extensions

Run this audit after every hardening change or software installation.

`[ROOT]`

```bash
# Confirm exact listening TCP and UDP ports
sudo lsof -nP -iTCP -sTCP:LISTEN
sudo lsof -nP -iUDP | grep -v '\*:\*'

# Confirm active PF state and packet counters
sudo pfctl -s info | head -n 20
sudo pfctl -a com.local.hardening -v -sr

# Confirm loaded Network/Endpoint Security System Extensions
systemextensionsctl list
```
