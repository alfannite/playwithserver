# Mobile Networking & Traffic Ops Bootstrap

Configuring Android Private DNS (DNS-over-TLS), WireGuard/Tailscale tunnels, PCAPdroid packet inspection, `gnirehtet` USB reverse tethering, and baseline `ip`/`ss` diagnostics.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Android Single-VPN-Slot Constraint](#android-single-vpn-slot-constraint)
- [Configure Private DNS (DNS-over-TLS)](#configure-private-dns-dns-over-tls)
- [Bootstrap WireGuard and Tailscale](#bootstrap-wireguard-and-tailscale)
- [Install PCAPdroid for Traffic Inspection](#install-pcapdroid-for-traffic-inspection)
- [Install gnirehtet for USB Reverse Tethering](#install-gnirehtet-for-usb-reverse-tethering)
- [Verify Network Interfaces and Routes](#verify-network-interfaces-and-routes)

## Android Single-VPN-Slot Constraint

Android permits only **one active `VpnService` interface (`tun0`) per user profile** at a time. Starting a second `VpnService` app immediately tears down the first.

| Tool | Uses `VpnService`? | Coexists with WireGuard/Tailscale? |
| --- | --- | --- |
| WireGuard (userspace) / Tailscale | Yes | Mutual exclusion — pick one active VPN |
| PCAPdroid (non-root mode) | Yes | No — disconnects active VPN |
| PCAPdroid (root `tcpdump` mode) | No (`[ROOT]`) | Yes — captures alongside active VPN |
| `gnirehtet` reverse tethering | Yes | No — uses `VpnService` to tunnel IP over ADB |
| Android Private DNS (DoT) | No (handled by `netd`) | Yes — works natively alongside any VPN |
| `adb forward` / `adb reverse` | No (ADB daemon socket) | Yes — works regardless of active VPN |

## Configure Private DNS (DNS-over-TLS)

Android 9+ supports native system-wide DNS-over-TLS (TCP port 853) inside `netd` without consuming the `VpnService` slot.

### Common Verified DoT Hostnames

| Provider | Private DNS Hostname (`private_dns_specifier`) | Behavior |
| --- | --- | --- |
| Quad9 (Malware blocking + DNSSEC) | `dns.quad9.net` | Privacy-focused security filtering |
| AdGuard DNS | `dns.adguard-dns.com` | Ad/tracker blocking |
| NextDNS (Custom profile) | `<profile-id>.dns.nextdns.io` | Per-device analytics, allowlists, blocklists |
| Cloudflare Security | `security.cloudflare-dns.com` | Malware filtering |

### Apply via ADB (No UI Navigation Needed)

`[NON-ROOT]` (Host workstation via ADB)

```bash
# Enforce strict DoT hostname mode (never silently falls back to plaintext UDP 53)
adb shell settings put global private_dns_mode hostname
adb shell settings put global private_dns_specifier dns.quad9.net

# Verify active Private DNS state in netd
adb shell settings get global private_dns_mode
adb shell settings get global private_dns_specifier
adb shell dumpsys dnsresolver | grep -E 'Private DNS|mode=|server=' | head -n 20
```

> **Watch out:** Strict `hostname` mode breaks captive-portal login pages on hotel/airport Wi-Fi that hijack plaintext DNS queries to redirect you to a login splash screen. Temporarily switch to `opportunistic` (`settings put global private_dns_mode opportunistic`) or `off` to sign in, then restore `hostname`.

## Bootstrap WireGuard and Tailscale

### WireGuard (`com.wireguard.android`)

1. Install **WireGuard** from F-Droid or Google Play.
2. Generate or import a peer configuration (`wg0.conf`) via QR code or file import.
3. For cellular networks behind CGNAT/IPv6-only carriers, set `MTU = 1280` and `PersistentKeepalive = 25` in the `[Interface]` / `[Peer]` sections:

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.66.66.10/32, fd42:42:42::10/128
DNS = 9.9.9.9
MTU = 1280

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
PresharedKey = <OPTIONAL_PSK>
Endpoint = vpn.example.com:51820
AllowedIPs = 10.66.66.0/24, 192.168.10.0/24
PersistentKeepalive = 25
```

- Set `AllowedIPs = 0.0.0.0/0, ::/0` only when tunneling all traffic through an exit node; scope to specific CIDRs (split tunnel) for homelab management without routing bulk traffic through home uplink.
- On **rooted** devices whose kernel includes the WireGuard kernel module (`lsmod | grep wireguard` or `/sys/module/wireguard`), open **WireGuard Settings -> Kernel module backend** to free Android's `VpnService` slot.

### Tailscale (`com.tailscale.ipn`)

1. Install **Tailscale** from F-Droid or Google Play and authenticate to your tailnet.
2. To route homelab LAN subnets or internet egress:
   - **Subnet Routes:** Approve advertised routes in the Tailscale admin console; Android automatically accepts subnet routes (verify **Use Tailscale subnets** is enabled in app settings).
   - **Exit Node:** Tap **Exit node** in the Android app to route all egress through a trusted server on untrusted Wi-Fi.
   - **Split-DNS / MagicDNS:** Enable **Use Tailscale DNS** to resolve internal `.ts.net` and corporate/homelab Split-DNS domains automatically.

## Install PCAPdroid for Traffic Inspection

1. Install **PCAPdroid** (`com.emanuelef.remote_capture`) from F-Droid or GitHub Releases.
2. Optional for HTTPS payload inspection in lab environments: install the companion **PCAPdroid-mitm** APK from the official GitHub Releases page (`emanuele-f/PCAPdroid-mitm`).
3. Launch PCAPdroid:
   - **Non-root:** Leave **Root capture** unchecked; select target app filter (or All apps) and tap **Ready** (creates local `VpnService`).
   - **Root (`[ROOT]`):** Enable **Settings -> Root capture** so PCAPdroid invokes `tcpdump` directly on `wlan0`/`rmnet_data*`/`tun0` without displacing WireGuard or Tailscale.

## Install gnirehtet for USB Reverse Tethering

`gnirehtet` gives an Android device with no Wi-Fi/SIM full internet connectivity through your host workstation's network over a standard USB ADB cable.

### Linux / macOS / Windows Host Install

`[NON-ROOT]` (Host workstation)

```bash
# Download the official Rust release bundle (contains host binary + gnirehtet.apk)
# Check latest tag at https://github.com/Genymobile/gnirehtet/releases
curl -fsSL -o /tmp/gnirehtet.zip \
  https://github.com/Genymobile/gnirehtet/releases/download/v2.5.1/gnirehtet-rust-linux64-v2.5.1.zip
mkdir -p "$HOME/.local/share/gnirehtet"
unzip -q -o /tmp/gnirehtet.zip -d "$HOME/.local/share/gnirehtet"
rm -f /tmp/gnirehtet.zip
```

On Windows, install via Scoop (`scoop install gnirehtet`) or download the `gnirehtet-rust-win64` ZIP.

### Start Reverse Tethering

`[NON-ROOT]` (Host workstation with USB ADB connected)

```bash
cd "$HOME/.local/share/gnirehtet"
# Installs gnirehtet.apk automatically on first run, opens ADB reverse tunnel, and starts relay
./gnirehtet run
```

Accept the Android **Connection request (VPN)** dialog on the phone screen once.

> **Watch out:** `gnirehtet` operates at L3/L4 over TCP/UDP relay via `adb reverse`. It does not forward ICMP (`ping` from the phone will not work even when HTTP/HTTPS/DNS work cleanly); always test reverse-tethered connectivity with `curl -I https://example.com` rather than `ping`.

## Verify Network Interfaces and Routes

Use modern `ip` and `ss` inside Termux or `adb shell` to verify active interfaces, cellular `464XLAT` translation, and listening sockets.

`[NON-ROOT]` (via `adb shell` or Termux)

```bash
# List active IPv4/IPv6 addresses across Wi-Fi (wlan0), cellular (rmnet_data*), CLAT (v4-rmnet*), and VPN (tun0)
ip -brief addr show

# Inspect Android's multi-table policy routing (main table is often empty on Android!)
ip rule show
ip route show table all | head -n 40

# Inspect active TCP/UDP sockets
ss -tunap 2>/dev/null || ss -tuna
```
