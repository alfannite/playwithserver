# macOS Networking and Security Tips and Tricks

Practical recipes for split-DNS via `/etc/resolver`, `pf` port forwarding and NAT, instant DNS cache flushing, multi-NIC route priority, packet capture on Apple virtual interfaces, and SSH socket security.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Split-Horizon DNS with /etc/resolver](#split-horizon-dns-with-etcresolver)
- [Packet Filter Port Forwarding and Rate Limiting](#packet-filter-port-forwarding-and-rate-limiting)
- [DNS Cache Flush and mDNSResponder Diagnostics](#dns-cache-flush-and-mdnsresponder-diagnostics)
- [Packet Capture with Process Metadata via tcpdump](#packet-capture-with-process-metadata-via-tcpdump)
- [Service Order Priority and Multi-Homed Routing](#service-order-priority-and-multi-homed-routing)
- [Certificate Trust Store Management via security CLI](#certificate-trust-store-management-via-security-cli)

## Split-Horizon DNS with /etc/resolver

macOS natively supports per-domain DNS routing via `/etc/resolver/<domain>` without installing `dnsmasq` or touching VPN profiles. `mDNSResponder` automatically reads files placed there.

`[ROOT]`

```bash
sudo mkdir -p /etc/resolver

# Route all *.internal.lan queries to 192.168.10.53 on non-standard port 5353 if needed
sudo tee /etc/resolver/internal.lan >/dev/null <<'EOF'
nameserver 192.168.10.53
search_order 1
timeout 3
EOF

# Verify mDNSResponder picked up the scoped resolver
scutil --dns | grep -A 6 "internal.lan"

# Test using macOS native resolver (not dig)
dscacheutil -q host -a name db.internal.lan
```

> **Watch out:** Files inside `/etc/resolver/` take effect for native macOS APIs (`curl`, `ssh`, browsers, Go with cgo) immediately, but `dig` and `nslookup` ignore `/etc/resolver/` completely. Use `dscacheutil -q host -a name <fqdn>` or `dns-sd -G v4v6 <fqdn>` to verify split-DNS behavior.

## Packet Filter Port Forwarding and Rate Limiting

Use a dedicated `pf` redirect anchor to forward privileged ports (e.g., `80`/`443`) to unprivileged local services (e.g., `8080`/`8443`) without running web servers as `root`.

### Port Forwarding Anchor (`/etc/pf.anchors/com.local.rdr`) `[ROOT]`

```text
# Redirect external and loopback traffic on 443 -> 8443
rdr pass on en0 inet proto tcp from any to any port 443 -> 127.0.0.1 port 8443
rdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port 8443
```

Wire it into `/etc/pf.local.conf` in strict PF section order (`scrub` -> `nat` -> `rdr` -> `filter`):

```text
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
rdr-anchor "com.local.rdr"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
load anchor "com.local.rdr" from "/etc/pf.anchors/com.local.rdr"
```

Validate and apply:

```bash
sudo pfctl -vnf /etc/pf.local.conf
sudo pfctl -ef /etc/pf.local.conf
sudo pfctl -a com.local.rdr -sn
```

### SSH Brute-Force Connection Throttling in PF `[ROOT]`

Add a persistent dynamic table to your filter anchor to block IPs exceeding 6 new SSH connections in 60 seconds:

```text
table <ssh_bruteforce> persist
block drop in quick from <ssh_bruteforce>

pass in quick proto tcp to any port 22 flags S/SA keep state \
  (max-src-conn 10, max-src-conn-rate 6/60, overload <ssh_bruteforce> flush global)
```

Inspect or unban entries live:

```bash
sudo pfctl -a com.local.custom -t ssh_bruteforce -T show
sudo pfctl -a com.local.custom -t ssh_bruteforce -T delete 203.0.113.42
```

> **Watch out:** PF requires translation rules (`nat-anchor`, `rdr-anchor`) to appear *above* filter rules (`anchor`, `pass`, `block`) in `/etc/pf.local.conf`. Placing `rdr-anchor` after a filter rule causes `pfctl -vnf` to fail with `Rules must be in order: options, normalization, queueing, translation, filtering`.

## DNS Cache Flush and mDNSResponder Diagnostics

Flush both Directory Service cache and `mDNSResponder` together after editing `/etc/hosts`, changing VPN routes, or updating DNS records.

`[ROOT]`

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Dump live mDNSResponder cache and active resolver stats to unified logs
sudo killall -INFO mDNSResponder
log show --last 30s --predicate 'process == "mDNSResponder"' --style compact | tail -n 40
```

## Packet Capture with Process Metadata via tcpdump

macOS `tcpdump` includes Apple-specific pseudo-interface `pktap` and `-k` metadata flags that tag every captured packet with the owning process name and PID—something standard Linux `tcpdump` cannot do natively.

`[ROOT]`

```bash
# Capture HTTPS handshakes across all interfaces and print Process Name + PID + Interface (-k NP)
sudo tcpdump -i pktap,all -k NP -n 'tcp[tcpflags] & tcp-syn != 0 and port 443'

# Filter live packet capture exclusively to a single process (e.g., curl or ssh)
sudo tcpdump -i pktap,en0 -k NP -Q 'proc=curl' -n

# Capture DNS traffic on all interfaces including utun VPN tunnels
sudo tcpdump -i any -n port 53
```

## Service Order Priority and Multi-Homed Routing

When a Mac connects to both Ethernet and Wi-Fi (or a Thunderbolt bridge), macOS routes default traffic over the highest-priority active service in `networksetup`.

`[ROOT]`

```bash
# Inspect current service priority order
networksetup -listnetworkserviceorder

# Prioritize wired Ethernet above Wi-Fi explicitly
sudo networksetup -ordernetworkservices "Ethernet" "Wi-Fi" "Thunderbolt Bridge"

# Inspect routing table including scoped interface routes (-r -n)
netstat -rn -f inet | head -n 30
```

## Certificate Trust Store Management via security CLI

Install internal Homelab or corporate Root CA certificates into the macOS System Keychain cleanly via CLI so `curl`, browsers, and Python/Node tools using Security.framework trust them automatically.

`[ROOT]`

```bash
# Add and trust an internal Root CA in the System Keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/internal-ca.crt

# Verify trusted admin certificates
security dump-trust-settings -d

# Remove an expired or revoked CA by SHA-1 hash
sudo security delete-certificate -Z <SHA1_HASH> /Library/Keychains/System.keychain
```
