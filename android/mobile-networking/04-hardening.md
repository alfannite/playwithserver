# Mobile Networking Hardening

Production-safe security baselines for Private DNS enforcement, Always-On VPN leak prevention, PCAPdroid MITM CA hygiene, ADB tunnel scoping, and WireGuard/Tailscale least-privilege access.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Hardening Baseline Matrix](#hardening-baseline-matrix)
- [Enforce Strict Private DNS (DNS-over-TLS)](#enforce-strict-private-dns-dns-over-tls)
- [Configure Always-On VPN Without Breaking Local Ops](#configure-always-on-vpn-without-breaking-local-ops)
- [Maintain Strict PCAPdroid MITM CA Hygiene](#maintain-strict-pcapdroid-mitm-ca-hygiene)
- [Clean Up ADB Port Forwarding Tunnels](#clean-up-adb-port-forwarding-tunnels)
- [Scope WireGuard AllowedIPs and Tailscale ACLs](#scope-wireguard-allowedips-and-tailscale-acls)

## Hardening Baseline Matrix

| Control | Production Baseline | Operational Impact |
| --- | --- | --- |
| Private DNS Mode | `hostname` (strict DoT: `dns.quad9.net` / NextDNS / AdGuard) | Prevents ISP/Wi-Fi DNS spoofing and plaintext query leakage |
| Always-On VPN | Enabled for WireGuard/Tailscale on roaming devices | Auto-reconnects VPN after boot and network handoffs |
| Block Connections Without VPN | Enabled on travel/untrusted Wi-Fi; evaluate LAN SSH impact on homelab nodes | Prevents cleartext leaks during VPN renegotiation |
| PCAPdroid MITM User CA | Never installed on daily drivers; remove immediately after lab testing | Eliminates local TLS interception attack surface |
| `adb forward` / `adb reverse` | Bound strictly to loopback (`127.0.0.1`) and purged with `--remove-all` after sessions | Prevents stale host-to-device socket bridges |
| Tailscale / WireGuard Scope | Restrict Android nodes via Tailscale ACL tags / minimal `AllowedIPs` | Limits blast radius if a mobile device is lost or compromised |

## Enforce Strict Private DNS (DNS-over-TLS)

Android's default `opportunistic` mode silently downgrades to unencrypted UDP port 53 whenever a hostile Wi-Fi router drops TCP port 853. Enforce `hostname` mode so `netd` validates the resolver's TLS certificate and refuses plaintext fallback.

`[NON-ROOT]` (Host workstation via ADB)

```bash
adb shell settings put global private_dns_mode hostname
adb shell settings put global private_dns_specifier dns.quad9.net

# Audit current state
adb shell 'printf "mode=%s specifier=%s\n" \
  "$(settings get global private_dns_mode)" \
  "$(settings get global private_dns_specifier)"'
```

## Configure Always-On VPN Without Breaking Local Ops

In **Android Settings -> Network & internet -> VPN -> Gear icon next to WireGuard/Tailscale**:
1. Enable **Always-on VPN**.
2. Decide carefully on **Block connections without VPN**:
   - **Mobile / untrusted Wi-Fi devices:** Turn **ON** to eliminate leak windows during Wi-Fi-to-5G handoffs.
   - **Headless homelab servers relying on local LAN SSH (`192.168.1.x:8022`):** Keep **Block connections without VPN** **OFF** (or verify your VPN client excludes `192.168.1.0/24` and keep USB ADB or Tailscale SSH as an independent access path) so a temporary VPN control-plane outage does not isolate the node from LAN management.

> **Watch out:** Enabling **Block connections without VPN** blocks `adb connect` over Wi-Fi (`Wireless ADB`) and LAN SSH unless the LAN subnet is excluded or routed via the VPN itself. Always verify remote access via your Tailscale/WireGuard IP before enabling strict kill-switch blocking on a headless phone.

## Maintain Strict PCAPdroid MITM CA Hygiene

When using `PCAPdroid-mitm` to decrypt HTTPS traffic during security testing or debugging, Android installs a self-signed root CA into the **User credentials** trust store.

- **Never** leave the `PCAPdroid-mitm` user CA installed after finishing a capture session.
- **Never** install a MITM CA on a primary personal phone containing banking, password manager, or enterprise SSO credentials.
- Immediately revoke the certificate after inspection: **Settings -> Security -> Encryption & credentials -> Trusted credentials -> User** (or **User credentials**) -> select **PCAPdroid** -> **Remove**.

Verify no lingering user-installed CAs remain via ADB:

`[NON-ROOT]`

```bash
# Empty directory means zero user-installed root CAs are present
adb shell ls -la /data/misc/user/0/cacerts-added/ 2>/dev/null || echo "Requires root or inspect in Settings -> Trusted credentials -> User"
```

## Clean Up ADB Port Forwarding Tunnels

Active `adb forward` and `adb reverse` rules persist for the lifetime of the host `adb` server or device USB connection. Stale `adb reverse` rules expose local workstation services (such as a dev database or local web admin panel on `127.0.0.1`) to *every* app running on the Android device.

`[NON-ROOT]` (Host workstation)

```bash
# Audit all active host-to-device and device-to-host tunnels
adb forward --list
adb reverse --list

# Purge all tunnels immediately after finishing debugging
adb forward --remove-all
adb reverse --remove-all
```

> **Watch out:** Any app on the Android device with the `INTERNET` permission can connect to ports exposed via `adb reverse tcp:<port> tcp:<port>` on the device's `127.0.0.1`. Never leave `adb reverse` pointing to unauthenticated workstation databases, Docker sockets, or admin APIs after finishing development testing.

## Scope WireGuard AllowedIPs and Tailscale ACLs

Treat mobile devices and spare phone servers as lower-trust edge endpoints compared to datacenter servers:

- **WireGuard:** Give each Android device a unique keypair and `/32` tunnel IP. On the WireGuard server/router firewall, restrict that `/32` strictly to the specific management ports/hosts it needs—never give a phone unrestricted `0.0.0.0/0` access to your entire production RFC1918 core.
- **Tailscale:** Assign Android nodes an explicit tag (for example, `tag:android-edge`) in your Tailscale ACL policy and explicitly allow only required ingress/egress:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:android-edge:8022"]
    },
    {
      "action": "accept",
      "src": ["tag:android-edge"],
      "dst": ["tag:backup-server:22"]
    }
  ]
}
```
