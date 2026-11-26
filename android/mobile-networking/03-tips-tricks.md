# Mobile Networking Tips & Tricks

Live PCAPdroid-to-Wireshark USB streaming, working around Android's single-VPN-slot limit, USB-only SSH over `adb forward`, carrier IPv6/CGNAT survival patterns, and multi-table routing inspection.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Stream PCAPdroid Live to Host Wireshark Over USB](#stream-pcapdroid-live-to-host-wireshark-over-usb)
- [Work Around Android's Single-VPN-Slot Constraint](#work-around-androids-single-vpn-slot-constraint)
- [SSH Into Termux Over USB Without Wi-Fi or SIM](#ssh-into-termux-over-usb-without-wi-fi-or-sim)
- [Inspect Chrome and WebView via Abstract Unix Sockets](#inspect-chrome-and-webview-via-abstract-unix-sockets)
- [Navigate Mobile Carrier CGNAT and IPv6 464XLAT Quirks](#navigate-mobile-carrier-cgnat-and-ipv6-464xlat-quirks)
- [Tailscale Exit Nodes and Split-DNS for Homelab Nodes](#tailscale-exit-nodes-and-split-dns-for-homelab-nodes)

## Stream PCAPdroid Live to Host Wireshark Over USB

Avoid saving multi-gigabyte `.pcap` files to phone flash storage or exposing PCAPdroid's HTTP server on Wi-Fi by tunneling the live stream over USB ADB:

`[NON-ROOT]` (Host workstation)

```bash
# 1. In PCAPdroid on device: set Traffic dump -> HTTP server (default port 8080) and tap Start.
# 2. Forward device port 8080 to host loopback over USB ADB
adb forward tcp:8080 tcp:8080

# 3. Pipe live HTTP PCAP stream directly into Wireshark (Linux / macOS)
curl -fsS http://127.0.0.1:8080 | wireshark -k -i -

# Alternative: inspect live stream headlessly with tshark filtering HTTP/TLS SNI
curl -fsS http://127.0.0.1:8080 | tshark -r - -Y 'dns || tls.handshake.extensions_server_name' \
  -T fields -e frame.time_relative -e ip.dst -e dns.qry.name -e tls.handshake.extensions_server_name
```

## Work Around Android's Single-VPN-Slot Constraint

Because Android only allows one `VpnService` app per user, combine network functions intentionally:

| Goal | Non-Root Solution | Rooted Solution (`[ROOT]`) |
| --- | --- | --- |
| VPN + DNS ad/malware blocking | Tailscale/WireGuard (`VpnService`) + Android Private DNS (DoT) or NextDNS inside VPN DNS | Same, or AFWall+ + WireGuard kernel backend |
| VPN + Packet inspection | Not possible simultaneously on non-root | WireGuard/Tailscale (`VpnService`) + PCAPdroid Root Capture (`tcpdump`) |
| VPN + Per-app firewall | Not possible simultaneously on non-root (use VPN app's per-app include/exclude list) | AFWall+ (`iptables`/`ip6tables`) + WireGuard/Tailscale |
| Two simultaneous tunnels | Run WireGuard inside a separate Android Work Profile (Island/Shelter) — each user profile gets 1 `VpnService` | WireGuard kernel module backend + secondary userspace VPN |

> **Watch out:** Using Android's Work Profile gives the work profile its own independent `VpnService` slot, *not* chained nesting of two VPNs for the same app—only apps installed inside the Work Profile route through the Work Profile's VPN.

## SSH Into Termux Over USB Without Wi-Fi or SIM

When a pocket Linux server is completely offline (airplane mode, dead Wi-Fi, or lab bench setup), use `adb forward` to get full low-latency SSH and SFTP over USB:

`[NON-ROOT]` (Host workstation)

```bash
# Bind host 127.0.0.1:8022 to Termux sshd on device 127.0.0.1:8022
adb forward tcp:8022 tcp:8022

# Connect via SSH and transfer files via rsync over USB speeds
ssh -i ~/.ssh/id_ed25519_termux -p 8022 termux@127.0.0.1
rsync -avh -e "ssh -i ~/.ssh/id_ed25519_termux -p 8022" ./deploy/ termux@127.0.0.1:~/deploy/
```

Pair this with `gnirehtet run` in a second terminal if the offline phone also needs outbound internet access for `pkg upgrade` or pulling container/code dependencies.

## Inspect Chrome and WebView via Abstract Unix Sockets

Android browsers and embedded WebViews expose DevTools sockets on Linux's abstract Unix namespace (`@chrome_devtools_remote`, `@webview_devtools_remote_<pid>`), visible in `/proc/net/unix`:

`[NON-ROOT]` (Host workstation via ADB)

```bash
# Discover active abstract Unix sockets listening on the device
adb shell cat /proc/net/unix | grep -E 'devtools|localabstract'

# Forward Chrome's abstract socket to host TCP 9222
adb forward tcp:9222 localabstract:chrome_devtools_remote

# Query open tabs via JSON API from host
curl -s http://127.0.0.1:9222/json/list | jq '.[] | {title, url}'
```

## Navigate Mobile Carrier CGNAT and IPv6 464XLAT Quirks

Modern LTE/5G carriers assign phones an **IPv6-only** PDP context on `rmnet_data0` and synthesize IPv4 via **464XLAT** (`v4-rmnet_data0` interface with `192.0.0.4` RFC 7335 CLAT address) plus carrier-side **NAT64/CGNAT** (`100.64.0.0/10`).

### Operational Impacts & Fixes

1. **No inbound TCP/UDP reachability:** Never attempt DDNS + port forwarding on cellular data. Use outbound-initiated overlays (**Tailscale**, **WireGuard** with `PersistentKeepalive = 25`, or **`cloudflared`**).
2. **MTU fragmentation blackholes:** IPv6 + 464XLAT + WireGuard encapsulation reduces effective path MTU below 1500 bytes (often 1280–1380 bytes). Symptoms: small pings/DNS work, while SSH freezes after key exchange or HTTPS hangs during TLS handshake. Fix: explicitly set `MTU = 1280` in WireGuard `[Interface]`.
3. **Aggressive UDP NAT expiry:** Carriers drop idle UDP conntrack entries in 30–60 seconds. Keep WireGuard `PersistentKeepalive = 25` and prefer `cloudflared --protocol http2` over QUIC on cellular uplinks.

Inspect your carrier's exact addressing and policy tables:

`[NON-ROOT]` (via `adb shell` or Termux)

```bash
ip -brief addr show | grep -E 'rmnet|ccmni|clat|v4-|wlan|tun'
ip rule show
```

> **Watch out:** When testing connectivity on a dual-stack phone, `curl -4` forces IPv4 through the carrier's 464XLAT translator while `curl -6` uses native IPv6. Always test both `-4` and `-6` when debugging broken remote endpoints or WireGuard endpoints (`Endpoint = [2001:db8::1]:51820` vs IPv4).

## Tailscale Exit Nodes and Split-DNS for Homelab Nodes

- **Split-DNS without hijacking public DNS:** In the Tailscale Admin Console -> **DNS -> Nameservers -> Add nameserver -> Custom**, enable **Restrict to domain (Split DNS)** (for example, `home.arpa` or `internal.example.com` pointing to your homelab Pi-hole/Unbound IP `100.x.y.z`). Android resolves internal lab hosts through Tailscale while continuing to resolve public internet names through fast regional resolvers.
- **Avoid DNS loops on Exit Nodes:** If you enable an Android **Exit Node** while Android **Private DNS** is set to a custom hostname, ensure your exit node allows outbound TCP port 853; otherwise all DNS queries fail immediately once the exit node activates.
