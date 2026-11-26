# Mobile Networking Troubleshooting

Symptom-to-fix matrix and diagnostic workflows for Private DNS outages, single-VPN-slot collisions, PCAPdroid TLS errors, `gnirehtet` failures, carrier CGNAT/IPv6 MTU blackholes, and ADB socket forwarding issues.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Fix Private DNS Resolution Outages](#fix-private-dns-resolution-outages)
- [Resolve WireGuard and Tailscale Stalls on Cellular CGNAT/IPv6](#resolve-wireguard-and-tailscale-stalls-on-cellular-cgnatipv6)
- [Debug PCAPdroid Capture and MITM TLS Failures](#debug-pcapdroid-capture-and-mitm-tls-failures)
- [Fix gnirehtet Reverse Tethering Failures](#fix-gnirehtet-reverse-tethering-failures)
- [Debug adb forward and adb reverse Socket Errors](#debug-adb-forward-and-adb-reverse-socket-errors)
- [High-Signal Network Diagnostic One-Liners](#high-signal-network-diagnostic-one-liners)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause | Fix |
| --- | --- | --- | --- |
| `Private DNS server cannot be accessed` | `adb shell dumpsys dnsresolver` | Captive portal, Wi-Fi blocks TCP 853, or hostname typo | Verify hostname (`dns.quad9.net`), temporarily set `opportunistic` for captive login |
| Tailscale/WireGuard disconnects when starting PCAPdroid or `gnirehtet` | `adb shell ip addr show tun0` | Android single-`VpnService`-slot limit | Use PCAPdroid Root Capture (`tcpdump`) or WireGuard kernel backend (`[ROOT]`) |
| WireGuard connects (`handshake` OK) but HTTPS/SSH hangs on 4G/5G | `adb shell ip addr show tun0` | MTU > 1280 fragmented over carrier IPv6/464XLAT | Set `MTU = 1280` and `PersistentKeepalive = 25` in WireGuard config |
| PCAPdroid MITM shows `TLS handshake failed` | PCAPdroid Connections -> Error column | App ignores user CA (Android 7+) or enforces SSL pinning | Expected for pinned production apps; test only debug builds or unpinned lab setups |
| `gnirehtet` runs, VPN key icon shows, no DNS/internet on phone | `gnirehtet relay -d 9.9.9.9` | Host uses `127.0.0.53` stub DNS or host firewall blocks TCP 31416 | Pass explicit `-d 9.9.9.9,1.1.1.1` and allow loopback port 31416 on host |
| `adb reverse` returns `Connection refused` on phone | `ss -tlnp \| grep <port>` (host) | Host service listens only on `[::1]` or LAN IP, not `127.0.0.1` | Bind host server to `127.0.0.1` or `0.0.0.0` |
| `ip route` prints nothing on Android | `ip route show table all` | Android `netd` isolates routes in per-interface policy tables | Query `ip rule show` and `ip route show table all` |

## Fix Private DNS Resolution Outages

`[NON-ROOT]` (Host workstation via ADB)

```bash
# 1. Check current mode and configured hostname
adb shell settings get global private_dns_mode
adb shell settings get global private_dns_specifier

# 2. Inspect netd TLS validation status and failure counters
adb shell dumpsys dnsresolver | grep -E 'NetId|Private DNS|validation|tls' | head -n 35

# 3. Test whether outbound TCP 853 is blocked on the current Wi-Fi network (from Termux)
# nc -vz -w 3 dns.quad9.net 853
```

If TCP 853 is filtered by a restrictive corporate or hotel firewall, switch temporarily to `opportunistic` or connect through WireGuard/Tailscale first so DoT port 853 rides inside the encrypted VPN tunnel.

## Resolve WireGuard and Tailscale Stalls on Cellular CGNAT/IPv6

### Diagnosing MTU Blackholes

Symptom: small ICMP/DNS replies succeed, SSH connects and prints a banner, then freezes mid-handshake or when running `ls -la` / `cat`.

1. Inspect `tun0` MTU and carrier interface state:

`[NON-ROOT]` (via `adb shell` or Termux)

```bash
ip addr show tun0
ip addr show | grep -E 'rmnet|v4-|mtu'
```

2. Lower WireGuard `[Interface]` `MTU` to `1280` (the minimum IPv6 MTU guaranteed across LTE/5G 464XLAT paths).
3. Add `PersistentKeepalive = 25` under `[Peer]` so carrier CGNAT does not evict the UDP mapping while the phone screen is off.

### Diagnosing Tailscale DERP Fallback & Direct Path Issues

Inside Termux or via the Tailscale app diagnostics, note whether peer traffic is taking direct UDP or relaying through a DERP server:
- Cellular CGNAT (`hard NAT` / symmetric NAT) often prevents direct UDP hole-punching between two mobile peers; Tailscale automatically falls back to HTTPS/443 DERP relays. This is normal and requires no manual port forwarding, though latency increases slightly.
- If Tailscale disconnects while screen is off, exempt `com.tailscale.ipn` from Android Doze (`adb shell dumpsys deviceidle whitelist +com.tailscale.ipn`).

> **Watch out:** Some Android OEMs aggressively kill `WireGuard` or `Tailscale` background services during Deep Doze even when **Always-on VPN** is enabled. Always exempt your VPN client (`com.wireguard.android` / `com.tailscale.ipn`) via `dumpsys deviceidle whitelist` and set **Battery -> Unrestricted** in OEM App Info.

## Debug PCAPdroid Capture and MITM TLS Failures

- **No traffic captured in non-root mode:** Confirm no app filter is accidentally hiding the target package, and check that another `VpnService` did not steal the VPN slot.
- **`PCAPdroid-mitm` addon fails to start:** Ensure `PCAPdroid` and `PCAPdroid-mitm` versions match and **Battery optimization** is disabled for both APKs (Android kills the background MITM helper process aggressively on low-RAM phones).
- **Empty Wireshark window over `adb forward`:** Verify the forwarding rule is active and PCAPdroid HTTP dump mode is started *before* launching `curl`:

`[NON-ROOT]` (Host workstation)

```bash
adb forward --list
curl -v --max-time 3 http://127.0.0.1:8080 | head -c 64 | xxd
# Valid PCAP header starts with magic bytes: d4 c3 b2 a1 (or 0a 0d 0d 0a for pcapng)
```

## Fix gnirehtet Reverse Tethering Failures

`[NON-ROOT]` (Host workstation)

```bash
# 1. Confirm USB ADB sees the device cleanly
adb devices -l

# 2. Verify adb reverse tunnel on port 31416 was created by gnirehtet
adb reverse --list
# Expected: UsbFfs localabstract:gnirehtet tcp:31416

# 3. Restart relay with explicit DNS resolvers and verbose Rust logging
RUST_LOG=debug gnirehtet relay -d 9.9.9.9,1.1.1.1
```

If `gnirehtet` prints `Cannot connect to 127.0.0.1:31416`:
- Check host firewall rules (`ufw`, `firewalld`, Windows Defender Firewall) to ensure loopback TCP `31416` is allowed.
- Kill any orphaned `gnirehtet` process holding port `31416` (`ss -tlnp | grep 31416` on Linux or `Get-NetTCPConnection -LocalPort 31416` on Windows).

> **Watch out:** Android apps that explicitly query Android's `ConnectivityManager` for `NET_CAPABILITY_VALIDATED` or active Wi-Fi/cellular transport (such as Google Play Store downloads or certain OEM updaters) may report "Offline" when using `gnirehtet` on airplane mode even though browsers, Termux `pkg`, and `curl` have full internet connectivity.

## Debug adb forward and adb reverse Socket Errors

`[NON-ROOT]` (Host workstation)

```bash
# Check for port conflicts on host before forwarding
ss -tlnp | grep ':8022'

# List and clear stale ADB socket bindings
adb forward --list
adb reverse --list
adb forward --remove-all
adb reverse --remove-all

# Re-create and test TCP reachability directly
adb forward tcp:8022 tcp:8022
nc -vz -w 2 127.0.0.1 8022
```

If `adb forward` fails with `error: cannot bind listener: Address already in use`, pick a different host-side port (first argument): `adb forward tcp:18022 tcp:8022`.

## High-Signal Network Diagnostic One-Liners

`[NON-ROOT]` (via `adb shell` or Termux)

```bash
# Complete interface, IPv4/IPv6 address, and link-state overview
ip -brief addr show

# Show Android active default network, transport (WIFI/CELLULAR/VPN), and DNS servers
adb shell dumpsys connectivity | grep -E 'Active default network|NetworkAgentInfo|DnsAddresses|LinkAddresses' | head -n 30

# Show all routing tables and policy lookup rules
ip rule show && echo "---" && ip route show table all | head -n 50

# List active TCP connections and listening sockets (no legacy netstat)
ss -tulnp 2>/dev/null || ss -tuln
```
