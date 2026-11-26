# ADB & Fastboot Tips & Tricks

High-leverage ADB workflows, A/B slot flashing safety patterns, user-0 debloat rollback routines, and automated telemetry extraction.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Multi-Device Targeting and Fleet One-Liners](#multi-device-targeting-and-fleet-one-liners)
- [Safe User-0 Debloat and Rollback Workflow](#safe-user-0-debloat-and-rollback-workflow)
- [Fastboot A/B Slot Safety Patterns](#fastboot-ab-slot-safety-patterns)
- [Headless scrcpy and Broken-Screen Recovery](#headless-scrcpy-and-broken-screen-recovery)
- [Hardware Telemetry Extraction via dumpsys](#hardware-telemetry-extraction-via-dumpsys)
- [Fast APK Extraction and Input Automation](#fast-apk-extraction-and-input-automation)

## Multi-Device Targeting and Fleet One-Liners

Export `ANDROID_SERIAL` in your shell session to avoid repeating `-s <serial>` across commands when multiple USB and Wireless ADB targets are attached.

`[NON-ROOT]`

```bash
# Pin current terminal session to one device
export ANDROID_SERIAL="192.168.1.42:5555"
adb shell uname -a

# Run an identical read-only audit across all connected devices in parallel
adb devices | awk 'NR>1 && $2=="device" {print $1}' | \
  xargs -I{} -P4 sh -c 'echo "=== {} ===" && adb -s {} shell "getprop ro.product.model; dumpsys battery | grep -E \"level|temperature\""'
```

## Safe User-0 Debloat and Rollback Workflow

Before removing OEM packages, snapshot the current package state so any broken dependency can be restored in seconds without a factory reset.

### Step 1: Snapshot Enabled and Disabled Packages

`[NON-ROOT]`

```bash
adb shell pm list packages -e | sed 's/^package://' | sort > enabled-before.txt
adb shell pm list packages -d | sed 's/^package://' | sort > disabled-before.txt
```

### Step 2: Freeze First, Uninstall Only After Reboot Verification

`[NON-ROOT]`

```bash
# Phase 1: Disable (reversible with pm enable)
adb shell pm disable-user --user 0 com.facebook.appmanager
adb shell pm disable-user --user 0 com.facebook.services

# Phase 2: Remove from user 0 profile (-k preserves app data directory; omit -k to clear user data)
adb shell pm uninstall -k --user 0 com.facebook.appmanager
```

### Step 3: Instant Rollback (Re-Attach System Package to User 0)

`[NON-ROOT]`

```bash
# Re-enable a disabled package
adb shell pm enable com.facebook.services

# Restore an uninstalled system package (works even without APK files)
adb shell cmd package install-existing com.facebook.appmanager

# Diff current state against snapshot to find everything removed from user 0
comm -23 enabled-before.txt <(adb shell pm list packages -e | sed 's/^package://' | sort)
```

> **Watch out:** Some OEM packages reject `pm disable-user` with `SecurityException: Shell cannot change component state` yet accept `pm uninstall --user 0`. Before removing any unfamiliar package, inspect its provider and service bindings with `adb shell dumpsys package <pkg> | grep -E 'Provider|Service|required'` to confirm no core system component depends on it.

## Fastboot A/B Slot Safety Patterns

Modern Android devices (Android 9+ launched devices) use seamless A/B partitioning (`boot_a`/`boot_b`, `init_boot_a`/`init_boot_b`, `vbmeta_a`/`vbmeta_b`). Always leverage the inactive slot as a known-good fallback.

### Test Kernels and Patched Boot Images in RAM First

Never `fastboot flash` an untested boot image when `fastboot boot` is supported by the bootloader.

`[NON-ROOT]` `[REBOOT]`

```bash
# Check active slot before making changes
fastboot getvar current-slot

# RAM-only test boot: if it panics or bootloops, a hard power cycle boots the untouched flash image
fastboot boot ./patched_boot.img
```

### Switch Active Slot to Recover a Bootloop

If an OTA update or bad flash breaks slot `a`, switch to slot `b` without wiping userdata:

`[NON-ROOT]` `[DESTRUCTIVE]` `[REBOOT]`

```bash
# Check slot health attributes (slot-successful, slot-unbootable, slot-retry-count)
fastboot getvar all 2>&1 | grep -E 'current-slot|slot-successful|slot-unbootable|slot-retry-count'

# Flip active slot to the known-good side and reboot
fastboot --set-active=b
fastboot reboot
```

### vbmeta Caveats on Verified Boot (AVB 2.0)

Flashing modified `boot`, `vendor_boot`, or `recovery` partitions on some OEM devices (notably Samsung, Xiaomi, Realme, and Pixel with custom kernels) triggers a Verified Boot signature mismatch (`dm-verity corruption`).

`[DESTRUCTIVE]` `[REBOOT]`

```bash
# Only when required by a custom ROM/kernel installation guide:
# Flash stock vbmeta with AVB flags disabled (requires unlocked bootloader)
fastboot --disable-verity --disable-verification flash vbmeta ./vbmeta.img
```

> **Watch out:** Some chipsets (Qualcomm/MediaTek devices running Android 12+) refuse to boot existing encrypted userdata if `vbmeta` verification flags change without a factory data wipe (`fastboot -w`). Never run `--disable-verity --disable-verification` blindly on a production device unless you have a full off-device backup and confirmed your device tree requires it.

## Headless scrcpy and Broken-Screen Recovery

### Minimal Bandwidth Server Control

Run `scrcpy` on a 24/7 phone server with the physical OLED/LCD panel turned off to prevent burn-in and cut power draw by 50–70%:

`[NON-ROOT]`

```bash
scrcpy \
  --turn-screen-off \
  --stay-awake \
  --no-audio \
  --max-size=1024 \
  --video-bit-rate=2M \
  --max-fps=15 \
  --window-title="android-node-01"
```

Useful keyboard shortcuts inside `scrcpy` (default `MOD` is `Left Alt` or `Left Super`):

| Shortcut | Action |
| --- | --- |
| `MOD + o` | Turn device physical screen off (mirroring stays active) |
| `MOD + Shift + o` | Turn device physical screen back on |
| `MOD + h` / `MOD + b` | Home / Back |
| `MOD + n` | Expand notification shade |
| `MOD + p` | Toggle power button (wake/sleep) |
| `MOD + c` / `MOD + v` | Copy / Paste clipboard between host and Android |

### Control a Cracked-Digitizer Phone Without USB Debugging

If the touchscreen is dead and USB debugging was never enabled, `scrcpy --otg` emulates a physical USB HID keyboard and mouse over AOAv2 (Android Open Accessory) without needing ADB:

`[NON-ROOT]`

```bash
# Works over standard USB cable even on locked devices with ADB disabled
scrcpy --otg --keyboard=uhid --mouse=uhid
```

Use keyboard navigation (`Space`/`Enter`, PIN digits, `Tab`, arrow keys) to unlock the device and enable USB Debugging or trigger a backup.

## Hardware Telemetry Extraction via dumpsys

Poll battery temperature, voltage, charging state, and thermal throttling status in one shell call for monitoring scripts (Prometheus textfile collector, Nagios, cron):

`[NON-ROOT]`

```bash
adb shell '
  echo "--- BATTERY ---"
  dumpsys battery | grep -E "AC powered|USB powered|status:|level:|voltage:|temperature:"
  echo "--- THERMAL ---"
  dumpsys thermalservice | grep -E "Current status:|Temperature\{|mValue" | head -n 15
  echo "--- LOAD & MEM ---"
  cat /proc/loadavg
  free -m
'
```

Note that `dumpsys battery` reports `temperature` in tenths of a degree Celsius (`345` = `34.5 C`) and `voltage` in millivolts (`4120` = `4.12 V`).

## Fast APK Extraction and Input Automation

### Pull an Installed App's Exact APK(s) from a Device

`[NON-ROOT]`

```bash
# Find all APK paths (including split APKs) for a package and pull them locally
PKG="com.termux"
mkdir -p "./apk-${PKG}"
for p in $(adb shell pm path "$PKG" | tr -d '\r' | sed 's/^package://'); do
  adb pull "$p" "./apk-${PKG}/"
done
```

### Wake Screen and Dismiss Swipe Lock for Automation

`[NON-ROOT]`

```bash
# Send KEYCODE_WAKEUP (224) and swipe up from bottom to dismiss non-PIN lockscreen
adb shell input keyevent 224
adb shell input swipe 500 1800 500 600 200
```

Never hardcode unlock PINs in shell history or scripts (`input text`); unlock manually via `scrcpy` or use SSH into Termux for unattended headless administration.
