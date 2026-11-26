# Headless Mac Server Hardening

Security baseline tailored for 24/7 headless Mac Mini servers covering SSH-only administration, Screen Sharing isolation, Packet Filter rules compatible with OrbStack/Colima/Tailscale, update governance, and physical/encryption trade-offs.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Lock Down SSH and Disable Password Authentication](#lock-down-ssh-and-disable-password-authentication)
- [Isolate Screen Sharing and VNC to Loopback or Tailscale](#isolate-screen-sharing-and-vnc-to-loopback-or-tailscale)
- [Container-Safe Packet Filter Baseline](#container-safe-packet-filter-baseline)
- [Controlled OS Patching Without Unexpected Reboots](#controlled-os-patching-without-unexpected-reboots)
- [Minimize Exposed Local Services and TCC Surface](#minimize-exposed-local-services-and-tcc-surface)
- [Hardening Verification Checklist](#hardening-verification-checklist)

## Lock Down SSH and Disable Password Authentication

Harden OpenSSH via a high-priority drop-in in `/etc/ssh/sshd_config.d/` so Apple's `100-macos.conf` cannot override it.

`[ROOT]`

```bash
sudo tee /etc/ssh/sshd_config.d/10-mac-server.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers admin
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

sudo sshd -t
sudo sshd -T | grep -E "passwordauthentication|kbdinteractive|permitrootlogin|allowusers"
sudo launchctl kickstart -k system/com.openssh.sshd
```

> **Watch out:** Keep `AllowTcpForwarding yes` (or `local`) enabled if you rely on SSH port forwarding (`ssh -L 15900:127.0.0.1:5900`) to reach Screen Sharing or internal Docker dashboards. Setting `AllowTcpForwarding no` will sever SSH-tunneled VNC access.

## Isolate Screen Sharing and VNC to Loopback or Tailscale

Apple's Screen Sharing (`screensharingd`, TCP/UDP `5900`) binds to all interfaces (`*:5900`). Never expose port `5900` to untrusted networks or open router port forwards to it.

### Restrict Port 5900 via Packet Filter Anchor `[ROOT]`

Block direct LAN/WAN access to port `5900` on `en0` while allowing access exclusively over loopback (SSH tunnel) and Tailscale (`utun*` / `100.64.0.0/10`):

```text
# Inside /etc/pf.anchors/com.local.server
ext_if = "en0"
tailscale_net = "100.64.0.0/10"

# Deny direct Screen Sharing / VNC and SMB from physical LAN/WAN unless explicitly needed
block in quick on $ext_if proto { tcp, udp } to any port 5900
pass in quick proto tcp from $tailscale_net to any port 5900 keep state
```

### Disable Legacy VNC Password Auth `[ROOT]`

Always authenticate to Screen Sharing with macOS user accounts (Kerberos/SRP encrypted), never a weak 8-character legacy VNC password:

```bash
KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
sudo "$KICKSTART" -configure -clientopts -setvnclegacy -vnclegacy no
```

## Container-Safe Packet Filter Baseline

A headless Mac server running OrbStack, Colima, Lima, or Tailscale creates dynamic `bridge*`, `vmenet*`, and `utun*` interfaces. Scope `pf` filtering strictly to the physical NIC (`en0`) so container networking, VirtioFS, and Kubernetes pods continue operating cleanly.

### `/etc/pf.anchors/com.local.server` `[ROOT]`

```text
ext_if = "en0"
lan_admin = "{ 192.168.10.0/24, 100.64.0.0/10 }"

set block-policy drop
set skip on lo0

# Normalize inbound packets on physical NIC
scrub in on $ext_if all fragment reassemble

# Default inbound deny on physical Ethernet; preserve all stateful outbound
block in log on $ext_if all
pass out on $ext_if all keep state

# Rate-limited SSH from LAN admin subnet or Tailscale
table <ssh_ban> persist
block drop in quick on $ext_if from <ssh_ban>
pass in quick on $ext_if proto tcp from $lan_admin to ($ext_if) port 22 \
  flags S/SA keep state (max-src-conn 10, max-src-conn-rate 6/60, overload <ssh_ban> flush global)

# Allow Reverse Proxy HTTP/HTTPS if this Mac serves LAN/ingress web traffic
# pass in quick on $ext_if proto tcp to ($ext_if) port { 80, 443 } keep state

# Allow Tailscale direct WireGuard UDP and ICMP diagnostics from admin subnets
pass in quick on $ext_if proto udp to ($ext_if) port 41641 keep state
pass in quick on $ext_if inet proto icmp from $lan_admin to ($ext_if) icmp-type echoreq keep state
pass in quick on $ext_if inet6 proto icmp6 all icmp6-type { neighbrsol, neighbradv, routersol, routeradv } keep state
```

Validate before applying:

```bash
sudo pfctl -vnf /etc/pf.local.conf
```

> **Watch out:** If your Mac Mini runs both Ethernet (`en0`) and Wi-Fi (`en1`), disable Wi-Fi completely (`sudo networksetup -setairportpower en1 off` or disable the Wi-Fi network service) so an unfirewalled wireless interface does not bypass your `en0` PF rules.

## Controlled OS Patching Without Unexpected Reboots

Automatic macOS OS upgrades can trigger unsolicited reboots that stall at FileVault or interrupt long-running containers. Keep silent security data updates (`XProtect`, `Gatekeeper`) automatic while keeping full OS restarts manual under maintenance windows.

`[ROOT]`

```bash
# Keep XProtect and critical security data files automatic
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true

# Disable surprise unattended OS upgrades/reboots
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
```

## Minimize Exposed Local Services and TCC Surface

Turn off consumer desktop daemons that serve no purpose on a headless server.

`[ROOT]`

```bash
# Disable Bluetooth if no local HID peripherals are attached
sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0

# Disable Wi-Fi when running strictly on wired Ethernet
sudo networksetup -setnetworkserviceenabled "Wi-Fi" off

# Disable AirDrop, AirPlay Receiver, and Guest user
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
defaults write com.apple.controlcenter AirplayRecieverEnabled -bool false

# Enable Application Firewall in stealth mode while preserving signed Apple daemons
SFW="/usr/libexec/ApplicationFirewall/socketfilterfw"
sudo "$SFW" --setglobalstate on
sudo "$SFW" --setstealthmode on
sudo "$SFW" --setallowsigned on
```

## Hardening Verification Checklist

Run after setup and after every macOS point upgrade:

`[ROOT]`

```bash
# 1. Confirm only intended sockets are listening externally
sudo lsof -nP -iTCP -sTCP:LISTEN

# 2. Confirm FileVault / SIP / Gatekeeper posture matches your reboot design
fdesetup status
csrutil status
spctl --status

# 3. Confirm PF is active and blocking unintended inbound traffic on en0
sudo pfctl -s info | head -n 10
sudo pfctl -a com.local.server -sr

# 4. Confirm unattended reboot power policy is intact
pmset -g custom | grep -E "autorestart|sleep|disksleep|womp|powernap"
```
