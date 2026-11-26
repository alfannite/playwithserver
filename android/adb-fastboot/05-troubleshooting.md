# ADB & Fastboot Troubleshooting

Symptom-to-fix matrix, USB/udev/driver recovery workflows, Wireless ADB debugging, `scrcpy` failure resolution, and Fastboot bootloop diagnostics.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Fix ADB Unauthorized and Offline States](#fix-adb-unauthorized-and-offline-states)
- [Fix Linux udev and Windows Fastboot Driver Issues](#fix-linux-udev-and-windows-fastboot-driver-issues)
- [Debug Wireless ADB Pairing and Connection Failures](#debug-wireless-adb-pairing-and-connection-failures)
- [Resolve scrcpy Display and Encoder Failures](#resolve-scrcpy-display-and-encoder-failures)
- [Recover Fastboot Flashing and A/B Slot Errors](#recover-fastboot-flashing-and-ab-slot-errors)
- [High-Signal Diagnostic One-Liners](#high-signal-diagnostic-one-liners)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause | Fix |
| --- | --- | --- | --- |
| `device unauthorized` | `adb devices -l` | RSA fingerprint prompt unaccepted or expired | Unlock phone, accept dialog, or run `adb kill-server && adb start-server` |
| `device offline` | `adb devices -l` | Stale USB/TCP transport or outdated host `adb` | Replug cable, switch USB port (avoid USB 3 hubs), upgrade Platform-Tools |
| `???????????? no permissions` (Linux) | `lsusb` + `groups` | Missing `/etc/udev/rules.d/51-android.rules` or `plugdev` group | Install `51-android.rules`, add user to `plugdev`/`adbusers`, reload udev |
| `fastboot devices` empty (Windows) | `Get-PnpDevice` / `devmgmt.msc` | Bootloader interface unbound to Google USB Driver | Manually bind `Android Bootloader Interface` in Device Manager |
| `adb pair` hangs or fails | `nc -zv <ip> <pair-port>` | Wrong port (used connect port instead of pair port) or AP isolation | Re-read pairing dialog port; disable Wi-Fi client isolation on router |
| `scrcpy` shows black screen | `adb shell dumpsys window` | Target app sets `FLAG_SECURE` | Expected OS enforcement on non-root devices; test on Home screen |
| `FAILED (remote: 'Flashing is not allowed in Lock State')` | `fastboot getvar unlocked` | Bootloader is still locked | Enable OEM Unlocking in Developer Options, then unlock bootloader (wipes data) |
| `FAILED (remote: 'Partition not found')` on `system` | `fastboot getvar is-userspace` | Flashing logical dynamic partition from hardware bootloader | Run `fastboot reboot fastboot` to enter `fastbootd` first |
| Device bootloops after `pm uninstall --user 0` | `adb logcat -b crash` | Core OEM dependency removed | Run `adb shell cmd package install-existing <pkg>` during early boot ADB window |

## Fix ADB Unauthorized and Offline States

`[NON-ROOT]`

```bash
# Step 1: Kill stale daemon and verify only one adb binary exists on PATH
which -a adb
adb kill-server

# Step 2: Confirm host RSA keypair exists and is readable
ls -la "$HOME/.android/adbkey"*

# Step 3: Restart daemon and force a fresh USB handshake
adb start-server
adb reconnect offline
adb devices -l
```

If the RSA prompt never appears on the phone:
1. Toggle **USB debugging** off and back on.
2. Tap **Revoke USB debugging authorizations** in Developer Options.
3. Change the USB configuration notification from **Charging only** to **File Transfer (MTP)** or **PTP** (required on Xiaomi/HyperOS and Huawei devices before `adbd` activates).

## Fix Linux udev and Windows Fastboot Driver Issues

### Linux: Identify Missing Vendor ID and Add Rule

`[ROOT]`

```bash
# Find USB Vendor ID (first 4 hex digits after ID) while device is in ADB or Fastboot mode
lsusb
# Example: Bus 001 Device 009: ID 18d1:4ee0 Google Inc. Nexus/Pixel Device (fastboot)

# Add targeted rule if vendor/product is missing
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"' | \
  sudo tee /etc/udev/rules.d/51-android-custom.rules
sudo udevadm control --reload-rules && sudo udevadm trigger

# Check kernel USB errors (power brownout, cable fault, xHCI reset loops)
dmesg -T | tail -n 30
```

> **Watch out:** AMD Ryzen USB 3.x host controllers and unpowered USB-C hubs frequently drop Fastboot transfers mid-flash (`FAILED (Status read failed (Protocol error))`). Always connect directly to a motherboard USB 2.0 port when flashing firmware via Fastboot.

### Windows: Check Conflicting Drivers

`[ROOT]` (Elevated PowerShell)

```powershell
# List all ADB/Fastboot USB devices including errored/unknown ones
Get-PnpDevice -Status Error, Unknown | Format-Table Class, FriendlyName, InstanceId -AutoSize

# Check if another process is holding port 5037 (ADB server port)
Get-NetTCPConnection -LocalPort 5037 -ErrorAction SilentlyContinue |
  Select-Object LocalAddress, LocalPort, State, OwningProcess
```

## Debug Wireless ADB Pairing and Connection Failures

Wireless ADB uses **two distinct ephemeral ports**: one temporary port while the pairing dialog is open, and a separate daemon port shown on the main Wireless Debugging screen.

`[NON-ROOT]`

```bash
# Test L3 reachability to the phone's Wireless Debugging port
nc -vz -w 3 192.168.1.42 41205

# Inspect mDNS advertisements published by Android 11+ Wireless Debugging
adb mdns services

# Clear dead wireless endpoints before reconnecting
adb disconnect
adb connect 192.168.1.42:41205
```

If `nc -vz` times out while ping fails:
- Confirm host and phone are on the same Wi-Fi SSID/VLAN and **AP Isolation / Client Isolation** is disabled on the access point.
- Ensure Android did not put Wi-Fi to sleep or switch to cellular data when Wi-Fi had no upstream internet (captive portal / offline lab router).

## Resolve scrcpy Display and Encoder Failures

`[NON-ROOT]`

```bash
# List available hardware video encoders on the device (useful when default OMX/MediaCodec crashes)
scrcpy --list-encoders

# Fallback to a specific H.264 encoder and lower resolution when MediaCodec throws ConfigureException
scrcpy --video-codec=h264 --video-encoder='OMX.google.h264.encoder' --max-size=800 --video-bit-rate=2M

# Disable audio forwarding on Android < 11 (audio capture requires Android 11+)
scrcpy --no-audio
```

> **Watch out:** On Xiaomi (MIUI/HyperOS) devices, `scrcpy` displays the screen but ignores all mouse clicks and keyboard input until you enable **USB debugging (Security settings)** inside Developer Options (which requires a SIM card / Mi Account on stock MIUI).

## Recover Fastboot Flashing and A/B Slot Errors

### `fastboot: error: cannot generate image` or `sparse` failures

Upgrade to the latest Google Platform-Tools (`fastboot --version >= 34.0.0`). Old distribution builds fail to parse modern Android `super` and sparse images.

### Bootloop After Flashing `boot` / `init_boot`

1. Force reboot into bootloader (typically hold **Power + Volume Down** for 10–15 seconds).
2. Verify active slot and check whether the alternate slot is marked bootable:

`[NON-ROOT]` `[REBOOT]`

```bash
fastboot getvar current-slot
fastboot getvar slot-successful:a
fastboot getvar slot-successful:b

# Option A: Switch to the intact alternate slot
fastboot --set-active=b
fastboot reboot

# Option B: Re-flash stock boot / init_boot image to the broken slot
fastboot flash init_boot ./stock_init_boot.img
fastboot reboot
```

### Early-Boot ADB Recovery After Bad Debloat

If an accidental `pm uninstall --user 0` causes SystemUI to crash repeatedly while Android still starts `adbd`:

`[NON-ROOT]`

```bash
# Wait for adbd to come online during boot and immediately restore the removed package
adb wait-for-device shell cmd package install-existing com.android.systemui
adb reboot
```

## High-Signal Diagnostic One-Liners

`[NON-ROOT]`

```bash
# Capture only fatal Java exceptions and native tombstones from crash buffer
adb logcat -d -b crash -v threadtime | grep -E 'FATAL EXCEPTION|SIGSEGV|SIGABRT|Process:' -A 15

# Check why an app was killed (OOM, ANR, PhantomProcess, user stop) on Android 11+
adb shell dumpsys activity exit-info | head -n 80

# Identify top 10 memory-consuming processes on the device
adb shell dumpsys meminfo | sed -n '/Total PSS by process:/,/^$/p' | head -n 15

# Inspect active wake locks preventing deep sleep (or verify server wake-lock is held)
adb shell dumpsys power | grep -A 20 'Wake Locks:'
```
