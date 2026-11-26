# Termux Pocket Linux Hardening

Production-safe security controls for OpenSSH, `cloudflared` ingress, `proot-distro` isolation, and Android storage boundaries on a 24/7 Termux server.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Hardening Baseline Matrix](#hardening-baseline-matrix)
- [Harden OpenSSH Server Configuration](#harden-openssh-server-configuration)
- [Bind Local Services to Loopback Only](#bind-local-services-to-loopback-only)
- [Lock Down cloudflared Ingress and Credentials](#lock-down-cloudflared-ingress-and-credentials)
- [Minimize Shared Storage and proot-distro Exposure](#minimize-shared-storage-and-proot-distro-exposure)
- [Keep Packages Patched Safely](#keep-packages-patched-safely)

## Hardening Baseline Matrix

| Control | Production Baseline | Operational Impact |
| --- | --- | --- |
| SSH Authentication | Ed25519 keys only (`PasswordAuthentication no`) | Eliminates brute-force attacks; prevents blank-password logins |
| SSH Bind Scope | LAN IP / Tailscale IP / `127.0.0.1` (when behind `cloudflared`) | Prevents exposure when device roams onto untrusted Wi-Fi |
| Internal Web Apps | Listen strictly on `127.0.0.1:<port>` | Forces all external traffic through TLS reverse proxy or tunnel |
| `cloudflared` Credentials | `0600` on `~/.cloudflared/*.json`, Cloudflare Access policy on admin routes | Prevents credential theft and unauthenticated internet access |
| `proot-distro` Isolation | Run with `--isolated` and dedicated non-root user inside guest | Prevents guest environment from inheriting host Termux secrets |
| Physical Device Lock | Strong PIN/passphrase + disable ADB over TCP 5555 | Protects FBE encrypted userdata if device is physically stolen |

## Harden OpenSSH Server Configuration

Because Termux does not enforce Linux multi-user separation, anyone who gains an SSH session immediately owns all Termux data, SSH keys, and `~/storage/shared` files.

`[NON-ROOT]` (Termux shell)

```bash
# Enforce strict permissions on ~/.ssh and authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# Write hardened sshd_config
cat > "$PREFIX/etc/ssh/sshd_config" <<'EOF'
Port 8022
# If using cloudflared exclusively, change ListenAddress to 127.0.0.1
# If using LAN/Tailscale, restrict to specific interface IP or keep 0.0.0.0 behind firewall/VPN
ListenAddress 0.0.0.0

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

# Restrict authentication attempts and idle grace window
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 60
ClientAliveCountMax 3

# Disable unnecessary forwarding unless explicitly required
AllowAgentForwarding no
X11Forwarding no
PrintMotd no

# Modern host key and cipher hygiene (Ed25519 host key)
HostKey /data/data/com.termux/files/usr/etc/ssh/ssh_host_ed25519_key
Subsystem sftp /data/data/com.termux/files/usr/libexec/sftp-server
EOF

# Validate syntax before restarting so you do not lock yourself out
sshd -t && sv restart sshd
```

> **Watch out:** Never disable `PasswordAuthentication` and restart `sshd` before verifying your Ed25519 public key works in a *second* simultaneous SSH terminal. Keep your first working SSH session open until the new connection authenticates cleanly.

## Bind Local Services to Loopback Only

Any Termux process listening on `0.0.0.0` is immediately reachable by every host on the same Wi-Fi LAN (and, on some misconfigured hotspots, peer clients). Bind internal services (`gitea`, `syncthing` GUI, `code-server`, Prometheus exporters, Python APIs) strictly to `127.0.0.1` and publish them only via SSH port forwarding (`ssh -L`), Tailscale, or `cloudflared`.

Audit all active listeners regularly using `ss`:

`[NON-ROOT]` (Termux shell)

```bash
ss -tulpn
```

Confirm that only `sshd` (port 8022, if LAN SSH is intended) binds `0.0.0.0` or `*`, while application backends bind `127.0.0.1`.

## Lock Down cloudflared Ingress and Credentials

- Protect tunnel JSON credentials and certificates:

`[NON-ROOT]`

```bash
chmod 700 ~/.cloudflared
chmod 600 ~/.cloudflared/*.json ~/.cloudflared/cert.pem 2>/dev/null
```

- Always terminate `~/.cloudflared/config.yml` with a catch-all `- service: http_status:404` rule so unmatched hostnames never leak local services.
- For any administrative HTTP service or SSH endpoint exposed through `cloudflared`, enforce a **Cloudflare Zero Trust Access Application** policy (email OTP, GitHub/Google IdP, or mTLS) in the Cloudflare dashboard so unauthenticated internet scanners are blocked at the Cloudflare edge before traffic ever reaches your phone.

## Minimize Shared Storage and proot-distro Exposure

### Android Shared Storage Boundary

Once you run `termux-setup-storage`, every script or compromised web app running inside Termux can read and overwrite `/sdcard` (photos, downloads, documents). If your dedicated spare phone is strictly a server, keep `/sdcard` empty of personal files—or revoke Android's **Files and media** permission for Termux in **Android Settings -> Apps -> Termux -> Permissions** if none of your server workloads need `/sdcard`.

### Run `proot-distro` Services as a Non-Root Guest User

Even though `proot` root is emulated, running web services inside a dedicated guest user prevents accidental overwrites of `/etc` or binaries inside the guest rootfs and isolates environment variables (`--isolated` clears `$PREFIX`, `$TERMUX_*`, and host API tokens):

`[NON-ROOT]` (Inside `proot-distro login debian`)

```bash
adduser --disabled-password --gecos "" svcuser
```

Launch workloads from Termux with:

`[NON-ROOT]` (Termux shell)

```bash
proot-distro login debian --isolated --user svcuser -- /usr/local/bin/my-service
```

> **Watch out:** Android File-Based Encryption (FBE) locks `/data/data/com.termux/files/home` until the user enters the screen lock PIN once after a cold boot. If your unattended phone server loses power and reboots, `Termux:Boot` cannot start `sshd` or `cloudflared` until the PIN is entered. For physically secured homelab nodes that must auto-recover after power outages, evaluate the trade-off carefully: either pair the phone with a UPS/power bank + PIN lock, or use a dedicated server-only device with no personal accounts/data stored on it.

## Keep Packages Patched Safely

Termux is a rolling-release repository—partial upgrades (installing a new package without upgrading installed dependencies) frequently break shared libraries (`CANNOT LINK EXECUTABLE: library "libssl.so.3" not found`). Always upgrade cleanly as a single transaction:

`[NON-ROOT]` (Termux shell)

```bash
pkg update && pkg upgrade -y
```

Avoid running unattended blind `pkg upgrade -y` via cron without monitoring, because OpenSSH or `openssl` config prompts (`conffile` diffs) can stall non-interactive dpkg runs unless explicitly handled with `-o Dpkg::Options::="--force-confold"`.
