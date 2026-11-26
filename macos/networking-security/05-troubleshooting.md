# macOS Networking and Security Troubleshooting

Symptom-to-fix matrix, DNS resolution debugging (`scutil` vs `dig`), Packet Filter (`pf`) drop analysis, Gatekeeper/quarantine diagnosis, and firewall/VPN conflict recovery.

[← Back to macOS](../README.md) | [Home](../../README.md)

## Contents

- [Symptom to Diagnostic Matrix](#symptom-to-diagnostic-matrix)
- [DNS Resolves in dig But Fails in Apps or SSH](#dns-resolves-in-dig-but-fails-in-apps-or-ssh)
- [Diagnosing Packet Filter Drops Live](#diagnosing-packet-filter-drops-live)
- [Application Firewall Blocking Homebrew or Local Services](#application-firewall-blocking-homebrew-or-local-services)
- [Gatekeeper or Quarantine Blocking Signed or Internal Binaries](#gatekeeper-or-quarantine-blocking-signed-or-internal-binaries)
- [VPN Split-Tunnel and Route Table Conflicts](#vpn-split-tunnel-and-route-table-conflicts)
- [High-Signal Network Diagnostic One-Liners](#high-signal-network-diagnostic-one-liners)

## Symptom to Diagnostic Matrix

| Symptom | First Diagnostic Command | Likely Cause / Fix |
| :--- | :--- | :--- |
| `dig` works, but `ssh`/`curl` fails to resolve hostname | `scutil --dns && dscacheutil -q host -a name <host>` | Stale `mDNSResponder` cache or scoped VPN resolver; flush cache and check `/etc/resolver/*` |
| Inbound port open in `lsof`, unreachable over LAN | `sudo pfctl -s info && sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` | Blocked by `pf` anchor, `socketfilterfw`, or binary listening on `127.0.0.1` instead of `0.0.0.0` |
| `pfctl -ef` fails with syntax or rule order error | `sudo pfctl -vnf /etc/pf.local.conf` | Rules out of PF order (`scrub` -> `nat` -> `rdr` -> `filter`) or missing trailing newline at EOF |
| `"tool" cannot be opened because Apple cannot check it` | `xattr -l <path> && codesign -dvv <path>` | `com.apple.quarantine` set on unnotarized binary; verify hash and run `xattr -dr com.apple.quarantine` |
| SSH ignores `PasswordAuthentication no` in `sshd_config.d` | `sudo sshd -T \| grep -E "password\|kbd"` | `100-macos.conf` matched first; rename custom drop-in to `10-hardening.conf` |
| VPN connects but LAN or container traffic dies | `netstat -rn -f inet && scutil --nwi` | Full-tunnel `utun` default route overriding LAN/bridge CIDR or `pf` blocking `utun*` |
| `brew upgrade` breaks an inbound service silently | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps` | Binary signature changed after upgrade; re-unblock in `socketfilterfw` |
| TLS handshake fails with `unable to get local issuer certificate` | `security find-certificate -a -c "<CA>" /Library/Keychains/System.keychain` | Internal CA missing from System Keychain or not marked `trustRoot` |

## DNS Resolves in dig But Fails in Apps or SSH

### Step 1: Compare Native macOS Resolution vs Raw DNS `[NON-ROOT]`

```bash
# Native macOS mDNSResponder path (used by Safari, curl, ssh)
dscacheutil -q host -a name app.internal.lan

# Inspect scoped resolvers and search order
scutil --dns
```

### Step 2: Flush Caches and Check `/etc/resolver` `[ROOT]`

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Check for leftover VPN or OrbStack/Tailscale resolver files
ls -la /etc/resolver/ 2>/dev/null
```

### Step 3: Verify VPN Interface Scoped DNS Leaks `[NON-ROOT]`

If a disconnected VPN left stale DNS servers on `Wi-Fi` or `Ethernet`, reset the service back to DHCP DNS:

`[ROOT]`

```bash
networksetup -getdnsservers "Ethernet"
sudo networksetup -setdnsservers "Ethernet" Empty
```

> **Watch out:** `.local` hostnames are reserved by RFC 6762 for Bonjour multicast DNS (`mDNS`). Using `.local` for an internal unicast DNS zone causes multi-second lookup timeouts on macOS. Always use `.internal`, `.lan`, or a subdomain of a registered domain.

## Diagnosing Packet Filter Drops Live

macOS logs PF packets matching `block log` rules to virtual interface `pflog0`.

### Inspect Real-Time PF Drops `[ROOT]`

```bash
# Bring up pflog0 if not already active and stream blocked packets with rule numbers (-e)
sudo ifconfig pflog0 up
sudo tcpdump -n -e -ttt -i pflog0

# Correlate the logged rule number against active PF rules
sudo pfctl -vv -sr
sudo pfctl -a com.local.hardening -vv -sr
```

### Inspect Active NAT/State Table `[ROOT]`

```bash
# Count and filter active stateful connections
sudo pfctl -ss | grep ":22 " | head -n 30

# Kill stale states for a specific remote IP without flushing the whole table
sudo pfctl -k 203.0.113.42
```

## Application Firewall Blocking Homebrew or Local Services

### Step 1: Check Application Firewall Logs in Unified Logging `[ROOT]`

```bash
log show --last 15m --predicate 'subsystem == "com.apple.alf" OR process == "socketfilterfw"' --style compact
```

### Step 2: Re-Authorize Upgraded Binary `[ROOT]`

```bash
SFW="/usr/libexec/ApplicationFirewall/socketfilterfw"
BIN="/opt/homebrew/bin/caddy"

sudo "$SFW" --remove "$BIN"
sudo "$SFW" --add "$BIN"
sudo "$SFW" --unblockapp "$BIN"
```

## Gatekeeper or Quarantine Blocking Signed or Internal Binaries

### Diagnose Signature, Notarization, and Quarantine State `[NON-ROOT]`

```bash
TARGET="/Applications/InternalTool.app"

# Check quarantine extended attribute (contains download timestamp and origin app)
xattr -p com.apple.quarantine "$TARGET" 2>/dev/null

# Verify code signature integrity and notarization ticket
codesign --verify --deep --strict --verbose=2 "$TARGET"
spctl --assess --type execute --verbose=4 "$TARGET"
```

### Clear Quarantine Safely After Checksum Verification `[NON-ROOT]`

```bash
shasum -a 256 /path/to/downloaded-archive.tar.gz
xattr -dr com.apple.quarantine "$TARGET"
```

> **Watch out:** On Apple Silicon (`arm64`), macOS refuses to execute *any* completely unsigned native `arm64` binary with `SIGKILL (Code Signature Invalid)`—even when Gatekeeper is disabled. If you compile or patch a local binary manually, apply an ad-hoc signature with `codesign --force --sign - /path/to/binary`.

## VPN Split-Tunnel and Route Table Conflicts

### Trace Exact Route and Interface Selection `[NON-ROOT]`

```bash
# Check which interface and gateway macOS picks for a specific destination IP
route -n get 192.168.10.50
route -n get 1.1.1.1

# Inspect all utun interfaces and their assigned peer addresses
ifconfig | grep -A 4 "^utun"

# Inspect macOS network service reachability and DNS order
scutil --nwi
```

If a stuck VPN leaves orphaned routes after crashing, restart the interface cleanly:

`[ROOT]`

```bash
sudo networksetup -setnetworkserviceenabled "Ethernet" off
sleep 2
sudo networksetup -setnetworkserviceenabled "Ethernet" on
```

## High-Signal Network Diagnostic One-Liners

```bash
# Show all listening TCP sockets with owning user, PID, and bind address
sudo lsof -nP -iTCP -sTCP:LISTEN

# Test TLS certificate chain, SANs, and expiry directly against a remote endpoint
openssl s_client -connect example.internal:443 -servername example.internal </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# Inspect active ARP neighbor table (IPv4) and NDP table (IPv6)
arp -an
ndp -an

# Monitor live per-process external throughput for 10 seconds
nettop -P -t external -J bytes_in,bytes_out -d

# Measure TCP connection latency breakdown using curl
curl -s -o /dev/null -w "dns:%{time_namelookup}s tcp:%{time_connect}s tls:%{time_appconnect}s ttfb:%{time_starttransfer}s total:%{time_total}s\n" https://example.com
```
