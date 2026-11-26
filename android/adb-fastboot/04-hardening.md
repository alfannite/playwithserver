# ADB & Fastboot Hardening

Production-safe security baselines for ADB RSA keys, Wireless Debugging network exposure, Verified Boot integrity, and safe bootloader operations.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Hardening Baseline Matrix](#hardening-baseline-matrix)
- [Secure ADB Host RSA Keys](#secure-adb-host-rsa-keys)
- [Contain Wireless ADB Exposure](#contain-wireless-adb-exposure)
- [Harden USB Debugging Policy](#harden-usb-debugging-policy)
- [Bootloader Lock and Verified Boot Safety](#bootloader-lock-and-verified-boot-safety)
- [Verify Device Security Posture via ADB](#verify-device-security-posture-via-adb)

## Hardening Baseline Matrix

| Control | Recommended Production State | Impact on Operations |
| --- | --- | --- |
| `~/.android/adbkey` permissions | `0600` (owner read/write only) | None; prevents local workstation lateral movement |
| Legacy `adb tcpip 5555` | Disabled (`adb usb`) when not actively debugging | Eliminates unencrypted `0.0.0.0:5555` LAN exposure |
| Android 11+ Wireless Debugging | Enabled only on trusted management VLAN or toggled off after use | Ephemeral port + TLS pairing prevents passive sniffing |
| ADB Authorization Timeout | Enabled (7-day auto-revoke) on daily drivers; disabled only on dedicated lab servers | Forces periodic physical re-approval on mobile devices |
| Bootloader State | Locked on stock/AVB-signed ROMs (GrapheneOS); unlocked only when required by root/custom builds | Preserves hardware-backed Verified Boot chain |
| USB Debugging when idle | Disabled on untrusted physical hosts / travel devices | Prevents juice-jacking / unauthorized host enumeration |

## Secure ADB Host RSA Keys

Anyone who copies your host's `~/.android/adbkey` private key can authenticate silently to every Android device where you previously checked **Always allow from this computer**, bypassing the on-device RSA prompt.

### Audit and Restrict Host Key Permissions

`[NON-ROOT]`

```bash
# Linux / macOS: enforce strict owner-only permissions on ADB keypair
chmod 700 "$HOME/.android"
chmod 600 "$HOME/.android/adbkey"
chmod 644 "$HOME/.android/adbkey.pub"
ls -la "$HOME/.android/adbkey"*
```

### Rotate Compromised or Retired Host Keys

1. On the device: **Settings -> Developer options -> Revoke USB debugging authorizations**.
2. On the host: delete `~/.android/adbkey` and `~/.android/adbkey.pub`, then restart the ADB server to generate a fresh 2048-bit RSA keypair:

`[NON-ROOT]`

```bash
adb kill-server
rm -f "$HOME/.android/adbkey" "$HOME/.android/adbkey.pub"
adb start-server
```

## Contain Wireless ADB Exposure

Legacy `adb tcpip 5555` listens on all interfaces (`0.0.0.0:5555`) with no transport encryption. On shared LANs, any host with a previously authorized key—or an attacker probing for misconfigured devices—can connect.

### Immediately Revert TCP/IP Mode to USB-Only

`[NON-ROOT]`

```bash
# Disable TCP listener on port 5555 and restrict adbd to USB transport
adb usb

# Verify no TCP adbd listener remains on the device
adb shell ss -tlnp 2>/dev/null || adb shell cat /proc/net/tcp6 | grep -i 15B3
```

(`0x15B3` = decimal `5555`.)

### Prefer Android 11+ TLS Wireless Debugging or SSH

- Android 11+ Wireless Debugging (`adb pair` + `adb connect`) wraps ADB traffic in TLS 1.3 and binds an ephemeral high port only while Wireless Debugging is toggled on.
- For 24/7 headless phone servers on a LAN, disable Wireless Debugging permanently after initial bootstrap and use Termux `sshd` (Ed25519 key-only auth) or Tailscale/WireGuard instead of leaving `adbd` exposed on Wi-Fi.

> **Watch out:** Leaving `adb tcpip 5555` enabled on a device connected to a public or hotel Wi-Fi network exposes the ADB port to every peer on the same subnet. Even though modern Android requires RSA key authorization, older OEM builds and development ROMs (`ro.adb.secure=0`) accept unauthenticated shells immediately.

## Harden USB Debugging Policy

Use `adb shell settings` to inspect and control ADB timeout and security parameters without breaking active sessions.

`[NON-ROOT]`

```bash
# Check ADB authorization timeout in milliseconds (default 604800000 = 7 days; 0 = disabled)
adb shell settings get global adb_allowed_connection_time

# Enforce 7-day automatic revocation of unused host authorizations (recommended for carried devices)
adb shell settings put global adb_allowed_connection_time 604800000

# Verify ro.adb.secure=1 (must be 1 on production devices; 0 disables RSA key checks)
adb shell getprop ro.adb.secure
```

### Disable ADB Remotely After Completing Maintenance

If you finished bootstrapping a standalone server over ADB and have verified SSH/Tailscale access:

`[NON-ROOT]`

```bash
# Turns off Wireless Debugging (Android 11+)
adb shell settings put global adb_wifi_enabled 0

# Turns off USB Debugging (immediately disconnects your ADB session)
adb shell settings put global adb_enabled 0
```

## Bootloader Lock and Verified Boot Safety

Android Verified Boot (AVB 2.0) cryptographically verifies `boot`, `init_boot`, `dtbo`, `vendor_boot`, and `super` via `vbmeta` against hardware-fused keys before mounting partitions.

### Rules Before Running `fastboot flashing lock`

1. **Stock OS only (or explicit AVB custom-key ROMs):** Only lock the bootloader when running 100% unmodified OEM stock firmware or a ROM specifically engineered to flash a custom AVB signing key into `avb_custom_key` (for example, GrapheneOS on Pixel hardware).
2. **Never lock with root or modified `boot`/`vbmeta`:** Locking the bootloader while Magisk, KernelSU, custom recovery, or `--disable-verity` flags are present causes AVB verification to fail and can hard-brick devices that also disabled **OEM Unlocking** in Developer Options.
3. **Always verify OEM Unlocking state before locking** if you anticipate needing recovery access, though locking itself wipes userdata on compliant Android devices.

`[NON-ROOT]` (Read-only verification before any bootloader action)

```bash
adb shell getprop ro.boot.verifiedbootstate
# green  = locked bootloader, OEM stock key verified
# yellow = locked bootloader, custom AVB key verified (e.g., GrapheneOS)
# orange = unlocked bootloader (verification bypassed)
# red    = corruption / failed verification
```

> **Watch out:** Executing `fastboot flashing lock` triggers an automatic, irreversible factory reset (wipes `/data`) on standard Android bootloaders, and if the flashed partitions do not match the expected AVB root of trust, the device will refuse to boot into Android (`Your device is corrupt. It can't be trusted`). Always confirm stock images boot cleanly and pass `ro.boot.vbmeta.device_state` checks before locking.

## Verify Device Security Posture via ADB

Run this read-only audit script to inspect encryption, SELinux, Verified Boot, and security patch level without modifying device state:

`[NON-ROOT]`

```bash
adb shell '
  printf "Model:           %s\n" "$(getprop ro.product.model)"
  printf "Android:         %s (SDK %s)\n" "$(getprop ro.build.version.release)" "$(getprop ro.build.version.sdk)"
  printf "Security Patch:  %s\n" "$(getprop ro.build.version.security_patch)"
  printf "Verified Boot:   %s\n" "$(getprop ro.boot.verifiedbootstate)"
  printf "Flash Locked:    %s\n" "$(getprop ro.boot.flash.locked)"
  printf "ADB Secure:      %s\n" "$(getprop ro.adb.secure)"
  printf "Encryption:      %s (%s)\n" "$(getprop ro.crypto.state)" "$(getprop ro.crypto.type)"
  printf "SELinux:         %s\n" "$(getenforce 2>/dev/null || echo restricted)"
'
```
