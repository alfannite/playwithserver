# Elevated Android Ops Hardening

Production-safe security controls for root access scoping, SELinux enforcement hygiene, AFWall+ egress whitelisting, and module supply-chain safety.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Hardening Baseline Matrix](#hardening-baseline-matrix)
- [Scope Root and Shizuku Access Strictly](#scope-root-and-shizuku-access-strictly)
- [Keep SELinux Enforcing at All Times](#keep-selinux-enforcing-at-all-times)
- [Enforce Per-UID Egress Whitelisting](#enforce-per-uid-egress-whitelisting)
- [Audit Root Modules Before Flashing](#audit-root-modules-before-flashing)
- [Protect Hardware Against Unattended Root Escalation](#protect-hardware-against-unattended-root-escalation)

## Hardening Baseline Matrix

| Control | Production Baseline | Operational Impact |
| --- | --- | --- |
| Default Root Policy | Prompt + Biometric/PIN verification (Magisk) or Allowlist-only (KernelSU) | Prevents silent privilege escalation by compromised apps |
| SELinux Mode | `Enforcing` permanently (`getenforce == Enforcing`) | Preserves Android kernel sandbox and app isolation |
| Egress Firewall | AFWall+ Whitelist mode with IPv6 enabled + Startup leak protection | Blocks unapproved telemetry and rogue C2 egress per UID |
| Module Verification | Inspect `service.sh`, `post-fs-data.sh`, and binaries before install | Prevents malicious boot-level persistence |
| Shizuku Grants | Grant strictly to reviewed admin tools (Termux, Canta, Hail, App Ops) | Limits `uid=2000` Binder surface |
| Bootloader Unlock Trade-off | Physical security + strong screen lock PIN + disable ADB when idle | Mitigates unlocked-bootloader physical access risk |

## Scope Root and Shizuku Access Strictly

Granting unrestricted root to an untrusted app bypasses the entire Android permission model and allows silent theft of credentials from every other app's `/data/data/<pkg>/` directory.

- **Magisk:** Open **Settings -> Superuser**:
  - Set **Automatic Response** to **Prompt** (never **Grant**).
  - Set **Multiuser Mode** to **Only Owner**.
  - Enable **Require Biometric Authentication** (or PIN) for new root grants.
  - Enable **Superuser Access** -> **Apps and ADB** only when actively administering via USB; otherwise **Apps Only**.
- **KernelSU:** By design, `su` does not exist for any app until explicitly toggled on in **KernelSU Manager -> Superuser**. Enable **Unmount modules by default** so non-root apps cannot see overlay mounts.
- **Shizuku:** Periodically review **Shizuku -> Authorized applications** and revoke any app you no longer use.

## Keep SELinux Enforcing at All Times

Never disable SELinux (`setenforce 0`) as a shortcut to make a script or module work.

`[ROOT]`

```bash
# Confirm SELinux is Enforcing
getenforce

# Verify no boot script is silently calling setenforce 0
grep -rn "setenforce" /data/adb/modules/ /data/adb/service.d/ /data/adb/post-fs-data.d/ 2>/dev/null
```

If a legitimate root script or binary fails with `Permission denied` despite running as `uid=0`, inspect the exact SELinux AVC denial and fix the file label rather than disabling enforcement:

`[ROOT]`

```bash
# Inspect the exact source context (scontext), target context (tcontext), and denied permission
dmesg | grep 'avc: denied' | tail -n 15

# Repair mislabeled files copied into /data/adb or /system overlays
restorecon -Rv /data/adb/service.d/
# Or apply explicit system_file context to a standalone binary when appropriate
chcon u:object_r:system_file:s0 /data/adb/service.d/99-server-tuning.sh
```

> **Watch out:** Running `setenforce 0` does not merely help your root script—it disables SELinux mandatory access control for every browser, messaging app, and background service on the device, turning any single app RCE into trivial lateral movement across `/data`.

## Enforce Per-UID Egress Whitelisting

Rooted servers and hardened daily drivers should enforce default-deny outbound networking so OEM bloatware, analytics SDKs, and misconfigured services cannot phone home.

### Verify Dual-Stack Netfilter Enforcement

`[ROOT]`

```bash
# Confirm AFWall+ chains are loaded on both IPv4 and IPv6
iptables -S | grep -c 'afwall'
ip6tables -S | grep -c 'afwall'

# Verify no rogue app UID is bypassing rules (inspect active sockets and owning UIDs)
ss -tunp -e | head -n 40
```

Enable **AFWall+ -> Preferences -> Experimental -> Fix startup data leak** (writes an early boot script so apps cannot transmit during the 10–20 seconds before Android launches the AFWall+ app).

## Audit Root Modules Before Flashing

Every Magisk/KernelSU/APatch module executes arbitrary shell scripts as `uid=0` during boot. Treat module ZIPs with the same scrutiny as Linux kernel modules.

`[NON-ROOT]` (Host workstation or Termux before flashing)

```bash
# List all files inside a module ZIP before installing
unzip -l ./candidate-module.zip

# Inspect all boot-time shell scripts inside the archive
unzip -p ./candidate-module.zip customize.sh service.sh post-fs-data.sh 2>/dev/null | less
```

Red flags to reject immediately:
- Base64-encoded payloads (`eval "$(echo ... | base64 -d)"`) or opaque `curl | sh` downloads during boot.
- Calls to `setenforce 0` or modifications to `/data/misc/adb/adb_keys`.
- Unneeded Zygisk `.so` libraries bundled inside a module claiming to do simple `resetprop` or charging control.

> **Watch out:** An unlocked bootloader inherently allows an attacker with physical possession of the device to flash a malicious `boot`/`init_boot` image via Fastboot. File-Based Encryption (FBE) still protects `/data` as long as you use a strong alphanumeric passphrase/PIN and do not leave the device unlocked, so physical security remains mandatory on any rooted server.

## Protect Hardware Against Unattended Root Escalation

- Disable **USB debugging** when your rooted server is fully configured and reachable over key-only Termux SSH or Tailscale.
- Remove unused root shells from third-party apps; if only `accd` and `AFWall+` need root at runtime, do not keep `su` permanently granted to Termux or file managers unless actively needed.
- Monitor `/data/adb/` modification timestamps periodically to detect unexpected changes:

`[ROOT]`

```bash
find /data/adb/modules /data/adb/service.d /data/adb/post-fs-data.d -maxdepth 2 -ls
```
