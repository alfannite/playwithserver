# Mobile Networking Toolbelt

Categorized tool matrix, exact installation commands, production flags, and failure modes for PCAPdroid, WireGuard/Tailscale, `gnirehtet`, `adb forward`/`reverse`, Private DNS, `ip`/`ss`, and rooted `tcpdump`.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Tool Matrix](#tool-matrix)
- [PCAPdroid and PCAPdroid-mitm](#pcapdroid-and-pcapdroid-mitm)
- [WireGuard and Tailscale](#wireguard-and-tailscale)
- [gnirehtet](#gnirehtet)
- [adb forward and adb reverse](#adb-forward-and-adb-reverse)
- [Private DNS and dumpsys dnsresolver](#private-dns-and-dumpsys-dnsresolver)
- [ip and ss](#ip-and-ss)
- [tcpdump (Rooted Capture)](#tcpdump-rooted-capture)

## Tool Matrix

| Tool | Runs On | Privileges | Primary Use Case |
| --- | --- | --- | --- |
| PCAPdroid | Android | `[NON-ROOT]` (`VpnService`) or `[ROOT]` | Per-app packet capture, live PCAP stream, TLS MITM inspection |
| WireGuard / Tailscale | Android | `[NON-ROOT]` (`VpnService`) or `[ROOT]` (WG kernel) | Encrypted mesh/VPN, exit nodes, subnet routing, Split-DNS |
| `gnirehtet` | Host + Android | `[NON-ROOT]` (USB ADB) | Reverse tethering giving offline Android host internet |
| `adb forward` / `adb reverse` | Host + Android | `[NON-ROOT]` (ADB) | Bidirectional TCP and abstract Unix socket port forwarding |
| `settings` / `dumpsys dnsresolver` | Android | `[NON-ROOT]` (ADB shell) | System-wide DNS-over-TLS configuration and verification |
| `ip` / `ss` | Android (ADB / Termux) | `[NON-ROOT]` (full PIDs need `[ROOT]`) | Policy routing, carrier IPv6/464XLAT, and socket diagnostics |
| `tcpdump` | Android | `[ROOT]` | Full raw packet capture across real interfaces alongside active VPNs |

## PCAPdroid and PCAPdroid-mitm

Open-source Android packet capture and inspection app supporting non-root `VpnService` interception, rooted `tcpdump` capture, live Wireshark streaming, and optional TLS decryption.

### Install

Install **PCAPdroid** from F-Droid (`com.emanuelef.remote_capture`) and, only when decrypting TLS in a lab, **PCAPdroid-mitm** from GitHub Releases (`emanuele-f/PCAPdroid-mitm`).

### Real-World Usage (CLI Control via ADB Broadcast API & Live Stream)

`[NON-ROOT]` (Host workstation via ADB)

```bash
# Start a PCAPdroid capture targeting a single package and serving live PCAP over HTTP port 8080
adb shell am start -e action start \
  -e pcap_dump_mode http_server \
  -e app_filter com.example.targetapp \
  -n com.emanuelef.remote_capture/.activities.CaptureCtrl

# Forward PCAPdroid's local HTTP server over USB ADB and pipe directly into host Wireshark
adb forward tcp:8080 tcp:8080
curl -s http://127.0.0.1:8080 | wireshark -k -i -

# Stop capture cleanly via ADB broadcast
adb shell am start -e action stop -n com.emanuelef.remote_capture/.activities.CaptureCtrl
```

> **Watch out:** Starting with Android 7 (API 24), apps ignore user-installed CA certificates by default (`network_security_config`) unless the app explicitly opts in or is a debug build, and many apps enforce certificate pinning. Non-root `PCAPdroid-mitm` can only decrypt TLS for apps that trust user CAs (browsers, WebViews, debug builds); pinned production apps fail TLS handshakes unless tested on a rooted lab device with certificate unpinning.

## WireGuard and Tailscale

Production encrypted overlay networking clients for Android.

### Install

- **WireGuard:** F-Droid (`com.wireguard.android`) or Google Play.
- **Tailscale:** F-Droid (`com.tailscale.ipn`) or Google Play.

### Real-World Usage (CLI Verification via ADB / Termux)

`[NON-ROOT]` (verify active tunnel routes & DNS without touching GUI)

```bash
# Inspect tun0 interface IPv4/IPv6 addresses and MTU (look for MTU 1280 on mobile networks)
adb shell ip addr show tun0

# Inspect policy routing rules injected by Android VpnService
adb shell ip rule show | grep -E 'tun0|uidrange'

# Verify active Tailscale/WireGuard DNS servers in Android netd
adb shell dumpsys connectivity | grep -A 12 'VPN' | head -n 30

# Query WireGuard handshake and transfer counters (Rooted kernel backend only)
adb shell su -c 'wg show'
```

> **Watch out:** Android's **Block connections without VPN** setting prevents leaks when WireGuard or Tailscale drops, but it also blocks local RFC1918 LAN traffic (such as LAN SSH to Termux or Wireless ADB) unless **Bypass LAN** / **Allow local network access** is supported and enabled in the VPN client, or the local subnet is explicitly excluded.

## gnirehtet

USB reverse tethering relay written in Rust that routes Android device traffic through the host workstation's internet connection over ADB.

### Install

`[NON-ROOT]` (Host workstation)

```bash
# Windows (Scoop)
scoop install gnirehtet

# Arch Linux (AUR)
yay -S gnirehtet-rust-bin

# Linux / macOS: download official prebuilt archive from github.com/Genymobile/gnirehtet/releases
```

### Real-World Usage

`[NON-ROOT]` (Host workstation)

```bash
# Single-device interactive reverse tether (installs APK + starts client + runs relay)
gnirehtet run

# Auto-tether any Android device plugged into USB automatically (ideal for device labs)
gnirehtet autorun

# Run relay with explicit DNS servers (essential when host uses local stub resolver 127.0.0.53)
gnirehtet relay -d 9.9.9.9,1.1.1.1

# Target one specific device serial and stop reverse tethering cleanly
gnirehtet start 1A2B3C4D5E6F
gnirehtet stop 1A2B3C4D5E6F
```

> **Watch out:** On systemd-resolved Linux hosts (Ubuntu, Fedora), `/etc/resolv.conf` points to `127.0.0.53`, which Android cannot reach through `gnirehtet`'s default DNS forwarding unless you explicitly pass public or LAN DNS resolvers with `-d 9.9.9.9,1.1.1.1`.

## adb forward and adb reverse

Built-in ADB socket multiplexers for forwarding TCP ports and abstract Unix domain sockets bidirectionally over USB or Wireless ADB.

### Install

Bundled with `adb` (`android-platform-tools`).

### Real-World Usage

`[NON-ROOT]` (Host workstation)

```bash
# Forward HOST localhost:8022 -> DEVICE localhost:8022 (SSH into Termux over USB with zero Wi-Fi!)
adb forward tcp:8022 tcp:8022
ssh -p 8022 termux@127.0.0.1

# Reverse forward DEVICE localhost:3000 -> HOST localhost:3000 (let phone access host dev server)
adb reverse tcp:3000 tcp:3000

# Forward an Android abstract Unix domain socket (Chrome DevTools remote debugging protocol)
adb forward tcp:9222 localabstract:chrome_devtools_remote

# Audit active rules and clean up stale tunnels
adb forward --list
adb reverse --list
adb forward --remove tcp:8022
adb reverse --remove-all
```

> **Watch out:** `adb forward` binds strictly to host loopback (`127.0.0.1`), and `adb reverse` binds strictly to device loopback (`127.0.0.1`). If your host dev server binds only to IPv6 (`[::1]:3000`) or a specific LAN IP (`192.168.1.10:3000`), `adb reverse tcp:3000 tcp:3000` returns `Connection refused` until the server binds `127.0.0.1` or `0.0.0.0`.

## Private DNS and dumpsys dnsresolver

Android's built-in DNS-over-TLS (`netd` `DnsResolver`) controls and diagnostic output.

### Install

Preinstalled on Android 9+.

### Real-World Usage

`[NON-ROOT]` (Host workstation via ADB)

```bash
# Configure NextDNS profile over DoT
adb shell settings put global private_dns_mode hostname
adb shell settings put global private_dns_specifier abc123.dns.nextdns.io

# Inspect DNS resolver cache stats, active DoT servers, and TLS handshake status
adb shell dumpsys dnsresolver | grep -E 'NetId|Private DNS|TLS|validation' | head -n 30

# Revert to Opportunistic (Auto) or Off
adb shell settings put global private_dns_mode opportunistic
```

> **Watch out:** On Android, if an app hardcodes its own DNS-over-HTTPS (DoH) resolver (Chrome Secure DNS, Firefox, Cloudflare 1.1.1.1) or sends raw UDP queries to `8.8.8.8:53` directly instead of calling Android's `getaddrinfo()`, it bypasses Android's Private DNS setting completely. Verify actual egress using PCAPdroid.

## ip and ss

Modern Linux networking utilities from `iproute2` replacing deprecated `ifconfig`, `route`, and `netstat`.

### Install

Preinstalled on Android (`/system/bin/ip`, `/system/bin/ss`) and available in Termux via `pkg install -y iproute2`.

### Real-World Usage

`[NON-ROOT]` (via `adb shell` or Termux)

```bash
# Show concise IPv4/IPv6 addresses and UP/DOWN state per interface
ip -brief addr show

# Display all Android per-network routing tables (Wi-Fi, cellular, VPN each have separate tables)
ip route show table all

# Inspect IPv6 routes and detect carrier NAT64/464XLAT (v4-rmnet_data*)
ip -6 route show table all | head -n 30

# List listening TCP/UDP ports and established flows with numeric output
ss -tuln
ss -tn state established
```

> **Watch out:** Running plain `ip route` (without `table all`) on Android almost always prints empty output or only local link routes because Android `netd` places Wi-Fi, cellular, and VPN default routes inside separate numbered policy-routing tables selected by `ip rule` (UID ranges and fwmark). Always use `ip rule show` and `ip route show table all`.

## tcpdump (Rooted Capture)

Low-level libpcap packet capture for rooted Android devices when you need full-interface dumps without occupying Android's `VpnService` slot.

### Install

`[ROOT]` (Termux root repo)

```bash
pkg install -y root-repo && pkg install -y tcpdump
```

### Real-World Usage

`[ROOT]`

```bash
# Capture all packets across every interface (including wlan0, rmnet_data0, and tun0) to PCAP
su -c 'tcpdump -i any -s 0 -w /sdcard/Download/capture.pcap'

# Inspect live DNS and DoT (53/853) queries on Wi-Fi without saving to disk
su -c 'tcpdump -i wlan0 -nn -l "port 53 or port 853"'

# Stream raw tcpdump output over USB ADB directly into host Wireshark
adb exec-out "su -c 'tcpdump -i any -U -s 0 -w - not port 5555'" | wireshark -k -i -
```

> **Watch out:** When streaming `tcpdump` over Wireless ADB, always append `not port <adb-port>` (or capture over USB ADB with `adb exec-out`)—otherwise `tcpdump` captures its own ADB output packets in an exponential feedback loop that saturates Wi-Fi immediately.
