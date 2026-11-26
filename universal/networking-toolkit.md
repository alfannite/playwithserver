# Universal Networking Toolkit

Cross-platform CLI diagnostics for bandwidth testing, path latency, port discovery, packet capture, DNS resolution, HTTP timing breakdowns, and TLS inspection.

[← Home](../README.md)

## Contents

- [Quick Tool Matrix](#quick-tool-matrix)
- [Bandwidth Testing with iperf3](#bandwidth-testing-with-iperf3)
- [Path and Packet Loss Analysis with mtr](#path-and-packet-loss-analysis-with-mtr)
- [Host and Port Discovery with nmap](#host-and-port-discovery-with-nmap)
- [Packet Capture with tcpdump](#packet-capture-with-tcpdump)
- [DNS Inspection with dig and doggo](#dns-inspection-with-dig-and-doggo)
- [HTTP Timing and Debugging with curl](#http-timing-and-debugging-with-curl)
- [TLS Certificate and Cipher Debugging with openssl](#tls-certificate-and-cipher-debugging-with-openssl)

## Quick Tool Matrix

| Tool | Layer | Primary Job | Debian/Ubuntu | RHEL/Rocky | macOS (Homebrew) |
| --- | --- | --- | --- | --- | --- |
| `iperf3` | L4 | TCP/UDP throughput & jitter | `apt install iperf3` | `dnf install iperf3` | `brew install iperf3` |
| `mtr` | L3 | Continuous traceroute + loss % | `apt install mtr-tiny` | `dnf install mtr` | `brew install mtr` |
| `nmap` | L3/L4 | Port scan, service/TLS probe | `apt install nmap` | `dnf install nmap` | `brew install nmap` |
| `tcpdump` | L2–L7 | Live packet capture / PCAP | `apt install tcpdump` | `dnf install tcpdump` | Built-in (`/usr/sbin/tcpdump`) |
| `dig` | L7 | Authoritative/recursive DNS | `apt install dnsutils` | `dnf install bind-utils` | Built-in / `brew install bind` |
| `doggo` | L7 | Modern DNS (DoH/DoT/JSON) | GitHub release / `go install` | GitHub release | `brew install doggo` |
| `curl` | L4–L7 | HTTP/TLS timing & API testing | `apt install curl` | `dnf install curl` | Built-in / `brew install curl` |
| `openssl` | L5/L6 | TLS handshake & cert chain | `apt install openssl` | `dnf install openssl` | `brew install openssl@3` |

## Bandwidth Testing with iperf3

`[NON-ROOT]`
```bash
# Server side: run listener daemon on default port 5201 (exit after 1 test with -1)
iperf3 -s

# Client side: 10s upload test using 4 parallel TCP streams (saturates 10GbE+)
iperf3 -c 10.10.0.5 -P 4 -t 10

# Reverse test (server sends -> client receives; tests download direction)
iperf3 -c 10.10.0.5 -P 4 -R

# Bidirectional simultaneous test (detects half-duplex or asymmetric shaping)
iperf3 -c 10.10.0.5 --bidir -P 2

# UDP jitter and packet loss test at 500 Mbps target rate
iperf3 -c 10.10.0.5 -u -b 500M -t 10
```

> **Watch out:** `iperf3` is single-threaded per process; testing a 25GbE/40GbE link with `-P 1` often bottlenecks on a single CPU core rather than the NIC. Use `-P 4` to `-P 8` (or `iperf3` 3.16+ multi-threaded streams) and inspect `Retr` (TCP retransmissions) — high retransmissions with low throughput point to duplex mismatch, bufferbloat, or bad cabling/optics.

## Path and Packet Loss Analysis with mtr

`[ROOT]` (raw sockets on macOS and TCP/UDP probes on Linux require `sudo`)
```bash
# Non-interactive report: 100 probes, numeric IPs, show ASNs and wide hostnames
mtr -r -w -c 100 -n -z 1.1.1.1

# TCP SYN probe on port 443 (bypasses routers/firewalls that drop ICMP)
sudo mtr -r -w -c 50 -T -P 443 api.github.com

# Force IPv6 path trace
mtr -6 -r -w -c 50 2606:4700:4700::1111
```

> **Watch out:** Packet loss appearing at a single intermediate hop (e.g., 40% loss on hop 4) while the final destination shows **0% loss** is almost always ICMP control-plane rate-limiting on that router, not real data-plane packet loss. Real loss persists across all subsequent hops through the final target.

## Host and Port Discovery with nmap

`[ROOT]` (SYN scan `-sS` and OS detection `-O` require root; TCP connect `-sT` works non-root)
```bash
# Fast host discovery ping sweep across a /24 subnet (no port scan)
nmap -sn 192.168.10.0/24

# Verify specific server ports with service version detection (no DNS reverse lookup)
sudo nmap -sS -sV -n -p 22,80,443,5432,6443 10.10.20.15

# Full TCP port audit on a host at high speed (LAN/homelab only)
sudo nmap -sS -p- --min-rate 2000 -T4 -n 10.10.20.15

# Audit supported TLS versions and cipher suites on an HTTPS endpoint
nmap --script ssl-enum-ciphers -p 443 example.com

# Scan UDP services (DNS, NTP, SNMP, WireGuard)
sudo nmap -sU -p 53,123,161,51820 10.10.20.15
```

> **Watch out:** Only scan networks and hosts you own or have explicit written authorization to test. Aggressive timing (`-T4`/`--min-rate`) can exhaust connection tracking (`nf_conntrack`) tables on small office firewalls and IoT devices.

## Packet Capture with tcpdump

`[ROOT]`
```bash
# Capture HTTP/HTTPS traffic on any interface without DNS/port name resolution
sudo tcpdump -i any -nn 'tcp port 80 or tcp port 443'

# Write full packets (-s 0) to a rotating PCAP file for Wireshark analysis
sudo tcpdump -i eth0 -nn -s 0 -w /tmp/capture.pcap 'host 10.10.20.15 and not port 22'

# Inspect DNS queries and responses in real time
sudo tcpdump -i any -nn -l 'port 53'

# Capture only TCP SYN, FIN, and RST packets (fast handshake/reset triage)
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & (tcp-syn|tcp-fin|tcp-rst) != 0'

# Read an existing PCAP with ASCII payload preview and timestamps
tcpdump -r /tmp/capture.pcap -nn -A -tttt
```

> **Watch out:** When running `tcpdump` over an SSH session, always append `and not port 22` (or `and not host <your-client-ip>`) to your BPF filter; otherwise every printed line generates more SSH packets, creating a self-amplifying feedback storm.

## DNS Inspection with dig and doggo

`[NON-ROOT]`
```bash
# Short A/AAAA answer from a specific resolver
dig @1.1.1.1 +short AAAA cloudflare.com

# Full delegation trace from root servers (pinpoints stale glue or NS mismatches)
dig +trace +nodnssec example.com

# Verify DNSSEC chain validation (look for 'ad' flag in header)
dig @9.9.9.9 +dnssec +multi example.com A

# Reverse PTR lookup for an IP address
dig -x 1.1.1.1 +short

# Modern doggo equivalents: DoH, DoT, and JSON output for scripting
doggo AAAA example.com @https://cloudflare-dns.com/dns-query
doggo MX example.com @tls://dns.quad9.net --json
```

## HTTP Timing and Debugging with curl

`[NON-ROOT]`
```bash
# Full connection timing breakdown (DNS, TCP connect, TLS handshake, TTFB, total)
curl -o /dev/null -s -w 'dns=%{time_namelookup}s tcp=%{time_connect}s tls=%{time_appconnect}s ttfb=%{time_starttransfer}s total=%{time_total}s code=%{http_code}\n' https://example.com

# Test a specific backend IP while preserving SNI and Host header (pre-DNS cutover testing)
curl -I --resolve app.example.com:443:10.10.20.50 https://app.example.com/healthz

# Inspect response headers, redirect chain, and TLS handshake without body
curl -svIL https://example.com 2>&1 | grep -E '^\*|^[<>]'

# Force IPv4 or IPv6 explicitly to isolate dual-stack breakage
curl -4 -I https://example.com
curl -6 -I https://example.com
```

## TLS Certificate and Cipher Debugging with openssl

`[NON-ROOT]`
```bash
# Inspect leaf certificate, SANs, issuer, and expiry dates with SNI
echo | openssl s_client -servername example.com -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# Inspect the full presented certificate chain (catch missing intermediate certs)
echo | openssl s_client -showcerts -servername example.com -connect example.com:443 2>/dev/null \
  | grep -E 's:|i:|Verify return code'

# Test STARTTLS on SMTP (port 587) or Postgres/IMAP
echo | openssl s_client -starttls smtp -connect mail.example.com:587 -servername mail.example.com 2>/dev/null \
  | openssl x509 -noout -dates -subject

# Check if a local certificate matches its private key (hashes must be identical)
openssl x509 -noout -pubkey -in fullchain.pem | openssl pkey -pubin -outform der | sha256sum
openssl pkey -pubout -in privkey.pem -outform der | sha256sum
```

> **Watch out:** Always pass `-servername <fqdn>` to `openssl s_client` when connecting to an IP or multi-tenant reverse proxy (Nginx, Traefik, Cloudflare). Without SNI, the server returns its default fallback certificate rather than the virtual host certificate.
