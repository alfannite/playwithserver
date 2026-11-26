# SSH Mastery

Production OpenSSH client configuration, Ed25519 key lifecycle, ProxyJump chains, ControlMaster multiplexing, port forwarding, and non-lockout server hardening.

[← Home](../README.md)

## Contents

- [Key Generation and Lifecycle](#key-generation-and-lifecycle)
- [Client Config and Bastion Patterns](#client-config-and-bastion-patterns)
- [Connection Multiplexing with ControlMaster](#connection-multiplexing-with-controlmaster)
- [Tunneling and Port Forwarding](#tunneling-and-port-forwarding)
- [SSH Agent and Hardware Keys](#ssh-agent-and-hardware-keys)
- [Server Hardening Baseline](#server-hardening-baseline)
- [Troubleshooting SSH Failures](#troubleshooting-ssh-failures)

## Key Generation and Lifecycle

Use Ed25519 keys with a strong passphrase and explicit KDF rounds (`-a 100`). Only fall back to 4096-bit RSA for legacy network gear (old Cisco IOS / Juniper / iDRAC) that lacks Ed25519 support.

`[NON-ROOT]`
```bash
# Generate a modern Ed25519 key with 100 KDF rounds and descriptive comment
ssh-keygen -t ed25519 -a 100 -C "ops@workstation-2026" -f ~/.ssh/id_ed25519_prod

# Generate a FIDO2 hardware-backed resident key (YubiKey / SoloKey)
ssh-keygen -t ed25519-sk -O resident -O verify-required -C "yubikey-prod" -f ~/.ssh/id_ed25519_sk

# Copy public key to a remote server cleanly (sets proper 0700/0600 permissions)
ssh-copy-id -i ~/.ssh/id_ed25519_prod.pub admin@10.10.20.15

# Verify key fingerprint (SHA256) and inspect public key metadata
ssh-keygen -lf ~/.ssh/id_ed25519_prod.pub

# Change passphrase on an existing private key without rotating the keypair
ssh-keygen -p -a 100 -f ~/.ssh/id_ed25519_prod
```

| File / Directory | Required Permission | Failure Mode if Too Permissive |
| --- | --- | --- |
| `~/.ssh` | `0700` (`drwx------`) | `sshd` ignores `authorized_keys` under `StrictModes yes` |
| `~/.ssh/authorized_keys` | `0600` (`-rw-------`) | Public-key authentication silently falls back to password |
| `~/.ssh/id_*` (private keys) | `0600` (`-rw-------`) | OpenSSH client refuses to use key (`UNPROTECTED PRIVATE KEY FILE`) |
| `~/.ssh/config` | `0600` (`-rw-------`) | OpenSSH client aborts with `Bad owner or permissions` |
| `~/.ssh/id_*.pub` | `0644` (`-rw-r--r--`) | Safe to read publicly |

## Client Config and Bastion Patterns

Centralize host aliases, bastion hops, identity selection, and keepalives in `~/.ssh/config`. Keep `IdentitiesOnly yes` on every host block so OpenSSH does not iterate through every key in `ssh-agent` and trigger `Too many authentication failures`.

`[NON-ROOT]`
```sshconfig
# ~/.ssh/config

Host bastion-prod
    HostName 203.0.113.10
    User opsadmin
    Port 2222
    IdentityFile ~/.ssh/id_ed25519_prod
    IdentitiesOnly yes

# Reach private RFC1918 subnets transparently through bastion-prod
Host 10.20.*.* prod-db-*
    User opsadmin
    ProxyJump bastion-prod
    IdentityFile ~/.ssh/id_ed25519_prod
    IdentitiesOnly yes

# Multi-hop ProxyJump (jump1 -> jump2 -> target)
Host airgap-node
    HostName 172.30.1.50
    User root
    ProxyJump bastion-prod,10.20.0.5
    IdentityFile ~/.ssh/id_ed25519_airgap
    IdentitiesOnly yes

# Global defaults (always place at the bottom: first match wins in ssh_config)
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
    AddKeysToAgent yes
    HashKnownHosts yes
    Compression no
```

> **Watch out:** OpenSSH uses **first-match-wins** evaluation for `~/.ssh/config`. Placing `Host *` at the top overrides specific `Host` blocks below it for any directive already set.

## Connection Multiplexing with ControlMaster

Multiplexing reuses a single authenticated TCP connection across subsequent `ssh`, `scp`, `sftp`, `rsync`, and `ansible` calls, eliminating repeated TLS/SSH handshakes and 2FA prompts.

`[NON-ROOT]`
```bash
# Create the control socket directory with strict permissions first
mkdir -p ~/.ssh/cm && chmod 0700 ~/.ssh/cm
```

```sshconfig
# Add inside Host * in ~/.ssh/config
Host *
    ControlMaster auto
    ControlPath ~/.ssh/cm/%C
    ControlPersist 10m
```

```bash
# Inspect active multiplexed master connection
ssh -O check bastion-prod

# Gracefully close an active ControlMaster socket
ssh -O exit bastion-prod

# Bypass ControlMaster for a single diagnostic command
ssh -S none bastion-prod
```

| Token | Expansion | Why `%C` Matters |
| --- | --- | --- |
| `%C` | SHA1 hash of `%l%h%p%r` | Prevents hitting the 104–108 byte Unix domain socket path limit on long FQDNs |
| `%r@%h:%p` | `user@host:port` | Human-readable, but fails silently on long AWS/cloud hostnames |

## Tunneling and Port Forwarding

| Mode | Flag | Direction | Common Production Use |
| --- | --- | --- | --- |
| Local forward | `-L [bind:]lport:target:tport` | Client -> Remote | Access internal Postgres/Grafana/Proxmox UI via bastion |
| Remote forward | `-R [bind:]rport:local:lport` | Remote -> Client | Expose local dev webhook or NATted edge node onto public VPS |
| Dynamic SOCKS5 | `-D [bind:]lport` | Client -> Remote (SOCKS5) | Route browser or `curl --socks5-hostname` through private VPC |
| Background tunnel | `-f -N -T` | No shell, backgrounded | Run port-forward cleanly without allocating a PTY |

`[NON-ROOT]`
```bash
# Local forward: reach internal Postgres (10.20.1.5:5432) on localhost:15432
ssh -N -L 127.0.0.1:15432:10.20.1.5:5432 bastion-prod

# Dynamic SOCKS5 proxy on localhost:1080 (use --socks5-hostname to prevent DNS leaks)
ssh -f -N -D 127.0.0.1:1080 bastion-prod
curl --socks5-hostname 127.0.0.1:1080 https://internal.corp.local/health

# Remote reverse tunnel: expose local port 8080 on remote VPS port 9090
ssh -N -R 127.0.0.1:9090:127.0.0.1:8080 vps-edge

# Resilient reverse tunnel (exits immediately if bind fails; pair with systemd/autossh)
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -R 127.0.0.1:9090:127.0.0.1:8080 vps-edge
```

> **Watch out:** Remote forwards (`-R 0.0.0.0:9090:...`) bind only to `127.0.0.1` on the server unless `GatewayPorts clientspecified` (or `yes`) is set in the remote `/etc/ssh/sshd_config`. Prefer `GatewayPorts no` and place Nginx/Caddy on the remote loopback instead of exposing raw reverse tunnels publicly.

## SSH Agent and Hardware Keys

Avoid `ForwardAgent yes` globally. If a jump host is compromised, root on that jump host can hijack your forwarded `SSH_AUTH_SOCK` to authenticate to any downstream server while you are connected. Use `ProxyJump` instead—your private key never leaves your workstation.

`[NON-ROOT]`
```bash
# Load key into ssh-agent with a 4-hour lifetime and confirmation prompt
ssh-add -t 4h -c ~/.ssh/id_ed25519_prod

# List loaded keys and fingerprints
ssh-add -l

# Remove all keys from agent immediately
ssh-add -D

# Lock agent with a temporary passphrase without removing keys
ssh-add -x
```

## Server Hardening Baseline

Place overrides in `/etc/ssh/sshd_config.d/99-hardening.conf` instead of editing `/etc/ssh/sshd_config` directly so distribution upgrades do not trigger merge conflicts.

`[ROOT]`
```bash
cat <<'EOF' > /etc/ssh/sshd_config.d/99-hardening.conf
# Authentication
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
MaxAuthTries 3
LoginGraceTime 30

# Restrict to an explicit admin group or users
AllowGroups sshusers sudo wheel

# Disable unneeded attack surface
X11Forwarding no
PermitEmptyPasswords no
AllowAgentForwarding no
PermitUserEnvironment no
DebianBanner no

# Keepalives for dead peer cleanup
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Always validate syntax BEFORE reloading sshd
sshd -t && systemctl reload sshd || systemctl reload ssh
```

> **Watch out:** Always keep a verified root or sudo SSH session open in a second terminal when reloading `sshd`. Test a fresh login from a third terminal before closing the original session. Also verify that `Include /etc/ssh/sshd_config.d/*.conf` appears near the top of `/etc/ssh/sshd_config` (first-match-wins applies to `sshd_config`, too—especially on Ubuntu cloud-init images where `50-cloud-init.conf` may set `PasswordAuthentication yes`).

## Troubleshooting SSH Failures

| Symptom | Diagnostic Command | Cause & Fix |
| --- | --- | --- |
| `Permission denied (publickey)` | `ssh -vvv user@host` | Check `IdentitiesOnly yes`, wrong username, or bad permissions on remote `~/.ssh` (`0700`) / `authorized_keys` (`0600`) |
| `Too many authentication failures` | `ssh -o IdentitiesOnly=yes -i ~/.ssh/key user@host` | `ssh-agent` offered > `MaxAuthTries` keys before reaching the right one |
| Hang right after `expecting SSH2_MSG_KEX_ECDH_REPLY` | `ping -M do -s 1472 host` | Path MTU blackhole (common over WireGuard/PPPoE); lower interface MTU or clamp MSS |
| Slow login (10–30s delay before prompt) | `ssh -vvv` pauses at `GSSAPI` or reverse DNS | Set `GSSAPIAuthentication no` on client/server and `UseDNS no` in `sshd_config` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `ssh-keygen -R <host>` | Host rebuilt/re-imaged (or MITM); verify host key fingerprint out-of-band before removing old entry |
| Connection drops after idle minutes | Add `ServerAliveInterval 30` in `~/.ssh/config` | Stateful NAT/firewall timed out idle TCP session |
| Disconnect frozen terminal session | Press `Enter`, then `~.` | OpenSSH escape sequence cleanly terminates a dead TCP session without killing the local terminal |
