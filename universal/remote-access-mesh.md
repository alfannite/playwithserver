# Remote Access Mesh and Tunnels

Zero-trust overlays and encrypted point-to-point networking using Tailscale, raw WireGuard, Cloudflare Tunnel (`cloudflared`), and ZeroTier for hosts behind NAT or CGNAT.

[← Home](../README.md)

## Contents

- [Technology Selection Matrix](#technology-selection-matrix)
- [Tailscale Operations](#tailscale-operations)
- [Raw WireGuard Configuration](#raw-wireguard-configuration)
- [Cloudflare Tunnel (cloudflared)](#cloudflare-tunnel-cloudflared)
- [ZeroTier Mesh Basics](#zerotier-mesh-basics)
- [Troubleshooting Mesh and Tunnel Connectivity](#troubleshooting-mesh-and-tunnel-connectivity)

## Technology Selection Matrix

| Solution | Transport / Control | Best Fit | Key Caveat |
| --- | --- | --- | --- |
| **Tailscale** | WireGuard data plane + coordinated NAT traversal (DERP fallback) | Fast fleet admin, SSH ACLs, subnet routers, exit nodes, MagicDNS | Control plane is SaaS (or self-hosted via Headscale) |
| **Raw WireGuard** | Kernel-space UDP VPN (`wg0`), zero control plane | Site-to-site links, static VPS relays, maximum throughput, airgapped control | Requires at least one publicly reachable UDP endpoint or manual NAT punch |
| **Cloudflare Tunnel** | Outbound QUIC/HTTP2 from `cloudflared` to Cloudflare edge | Exposing HTTP/HTTPS apps or SSH behind CGNAT with zero open ports | HTTP traffic terminates TLS at Cloudflare edge; non-HTTP requires client `cloudflared` or WARP |
| **ZeroTier** | Custom L2/L3 encrypted mesh (supports broadcast/multicast) | Legacy protocols needing L2 Ethernet bridging or mDNS across WAN | Userspace data plane has slightly higher CPU overhead than kernel WireGuard |

## Tailscale Operations

### Install and Authenticate

`[ROOT]`
```bash
# Official Linux install script (adds apt/dnf/pacman repo cleanly)
curl -fsSL https://tailscale.com/install.sh | sh

# Join tailnet as a headless server with Tailscale SSH enabled
sudo tailscale up --ssh --accept-dns=true --accept-routes=false

# Authenticate non-interactively with a reusable tagged auth key (CI/VM templates)
sudo tailscale up --auth-key=tskey-auth-XXXXX --advertise-tags=tag:server --ssh
```

### Subnet Router and Exit Node

Enable IP forwarding before advertising subnets or acting as an exit node:

`[ROOT]`
```bash
cat <<'EOF' | sudo tee /etc/sysctl.d/99-tailscale.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# Advertise LAN subnet AND act as an exit node (approve in Tailscale admin console)
sudo tailscale up --advertise-routes=192.168.10.0/24 --advertise-exit-node

# Optimize Linux UDP GRO forwarding on modern kernels (improves throughput on 1GbE+)
NETDEV=$(ip -o route get 8.8.8.8 | awk '{print $5; exit}')
sudo ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
```

### Operational Inspection Commands

`[NON-ROOT]`
```bash
# Show peer connection state (direct vs DERP relay)
tailscale status

# Ping peer to verify whether traffic is direct UDP or relayed via DERP
tailscale ping 100.64.0.12

# Inspect NAT type, UDP reachability, and nearest DERP latencies
tailscale netcheck
```

> **Watch out:** Enabling `--accept-routes` on a Linux server that is **itself** inside the advertised subnet can create routing loops or cut off local LAN SSH. Only pass `--accept-routes` on remote clients that genuinely need access to advertised subnets, or exclude overlapping routes carefully.

### Minimal Least-Privilege Tailscale ACL (HuJSON)

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"],
    "tag:exit": ["autogroup:admin"]
  },
  "acls": [
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:server:22,443,8080"] },
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["autogroup:internet:*"] }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:admin"],
      "dst": ["tag:server"],
      "users": ["autogroup:nonroot"]
    }
  ]
}
```

## Raw WireGuard Configuration

### Key Generation

`[ROOT]`
```bash
# Install WireGuard tools
# Debian/Ubuntu: sudo apt install -y wireguard-tools
# RHEL/Rocky:    sudo dnf install -y wireguard-tools

umask 077
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
wg genpsk > /etc/wireguard/preshared.key
```

### Hub Server (`/etc/wireguard/wg0.conf`)

```ini
[Interface]
Address = 10.66.0.1/24
ListenPort = 51820
PrivateKey = <HUB_PRIVATE_KEY>
MTU = 1420

# Enable NAT for road-warrior clients (replace eth0 with your WAN NIC)
PostUp = nft add table ip wg_nat; nft 'add chain ip wg_nat postrouting { type nat hook postrouting priority srcnat; policy accept; }'; nft add rule ip wg_nat postrouting oifname "eth0" masquerade
PostDown = nft delete table ip wg_nat

[Peer]
# Client / Spoke Node 1
PublicKey = <CLIENT_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
AllowedIPs = 10.66.0.2/32
```

### Spoke / Client Behind NAT (`/etc/wireguard/wg0.conf`)

```ini
[Interface]
Address = 10.66.0.2/24
PrivateKey = <CLIENT_PRIVATE_KEY>
MTU = 1420

[Peer]
PublicKey = <HUB_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
Endpoint = vpn.example.com:51820
# Split-tunnel: route only VPN subnet; use 0.0.0.0/0, ::/0 for full tunnel
AllowedIPs = 10.66.0.0/24
# Required when spoke sits behind stateful NAT
PersistentKeepalive = 25
```

`[ROOT]`
```bash
# Bring interface up and enable at boot
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0

# Inspect handshake timestamps and transfer counters
sudo wg show

# Hot-reload config without dropping existing sessions
sudo wg syncconf wg0 <(sudo wg-quick strip wg0)
```

> **Watch out:** WireGuard does not re-resolve a peer's `Endpoint` DNS name automatically if the hub's dynamic IP changes later. Use a static IP for hubs or schedule a periodic `wg set wg0 peer <PUBKEY> endpoint vpn.example.com:51820` timer. Also drop MTU to `1280`–`1380` if traversing PPPoE or cellular CGNAT links where large TLS packets stall.

## Cloudflare Tunnel (cloudflared)

Expose internal web apps, SSH, or TCP services without opening any inbound firewall ports or holding a public IPv4 address.

`[ROOT]`
```bash
# Install on Debian/Ubuntu (see Cloudflare pkg repo for RHEL/macOS/Termux)
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared

# Option A: Remotely managed tunnel via Zero Trust dashboard token
sudo cloudflared service install <TUNNEL_TOKEN>
sudo systemctl status cloudflared
```

Option B — Locally managed config (`/etc/cloudflared/config.yml`) for GitOps/IaC workflows:

```yaml
tunnel: 8e39c2a1-xxxx-xxxx-xxxx-xxxxxxxxxxxx
credentials-file: /etc/cloudflared/8e39c2a1-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json

ingress:
  - hostname: grafana.example.com
    service: http://127.0.0.1:3000
  - hostname: ssh.example.com
    service: ssh://127.0.0.1:22
  - service: http_status:404
```

Access an SSH service published through Cloudflare Tunnel from a workstation (`~/.ssh/config`):

```sshconfig
Host edge-box
    HostName ssh.example.com
    User opsadmin
    ProxyCommand cloudflared access ssh --hostname %h
```

## ZeroTier Mesh Basics

`[ROOT]`
```bash
# Install ZeroTier One on Linux
curl -s https://install.zerotier.com | sudo bash

# Join a 16-hex-character ZeroTier network ID (then authorize node in my.zerotier.com)
sudo zerotier-cli join 8056c2e21c000001

# Check node status, assigned IPs, and peer path latency
sudo zerotier-cli info
sudo zerotier-cli listnetworks
sudo zerotier-cli listpeers
```

## Troubleshooting Mesh and Tunnel Connectivity

| Symptom | Diagnostic Command | Cause & Fix |
| --- | --- | --- |
| Tailscale stuck on DERP relay (high latency) | `tailscale netcheck` & `tailscale status` | Symmetric/hard NAT blocking UDP 41641; allow outbound/inbound UDP 41641 or enable UPnP/NAT-PMP on edge router |
| WireGuard shows `latest handshake` empty | `sudo wg show` + `sudo tcpdump -i any -nn udp port 51820` | Mismatched public/private/preshared keys, firewall blocking UDP 51820, or wrong `Endpoint` IP |
| WireGuard handshake succeeds, SSH hangs on large output | `ping -M do -s 1380 10.66.0.1` | MTU blackhole; lower `MTU = 1360` or `1280` in `[Interface]` |
| `cloudflared` fails to connect on restricted networks | `journalctl -u cloudflared -n 50` | Outbound UDP 7844 (QUIC) blocked; force `--protocol http2` over TCP 7844/443 |
| MagicDNS breaks local `.local` or internal DNS | `resolvectl status` / `tailscale status` | Configure Split DNS nameservers in Tailscale Admin Console instead of overwriting global DNS |
