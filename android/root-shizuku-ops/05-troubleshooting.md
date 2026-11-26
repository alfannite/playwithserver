# Elevated Android Ops Troubleshooting

Symptom-to-fix matrix and recovery procedures for root bootloops, `boot` vs `init_boot` mismatches, Shizuku/`rish` failures, ACC charging quirks, AFWall+ lockouts, and SELinux denials.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Recover from a Root Module Bootloop](#recover-from-a-root-module-bootloop)
- [Fix Wrong Partition Flashed (boot vs init_boot)](#fix-wrong-partition-flashed-boot-vs-init_boot)
- [Fix Shizuku and rish Connection Failures](#fix-shizuku-and-rish-connection-failures)
- [Debug ACC Charging Switch and Idle Mode Failures](#debug-acc-charging-switch-and-idle-mode-failures)
- [Recover from AFWall+ Network Lockout](#recover-from-afwall-network-lockout)
- [Diagnose SELinux AVC Denials](#diagnose-selinux-avc-denials)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause | Fix |
| --- | --- | --- | --- |
| Bootloop right after installing Magisk/KSU module | `adb logcat -b crash` during boot | Incompatible Zygisk/overlay module | Trigger Safe Mode or run `adb wait-for-device shell magisk --remove-modules` |
| Bootloop right after `fastboot flash` | `fastboot getvar current-slot` | Patched wrong partition (`boot` vs `init_boot`) or wrong OS build image | Flash unmodified stock image to active slot or switch A/B slot |
| `Magisk` installed shows `N/A` after flashing `boot.img` | `fastboot getvar partition-size:init_boot_a` | Android 13+ GKI device stores ramdisk in `init_boot`, not `boot` | Restore stock `boot.img` and patch/flash `init_boot.img` instead |
| Shizuku stops randomly on screen off | `adb shell dumpsys activity exit-info` | OEM battery killer or Wireless Debugging turned off | Whitelist `moe.shizuku.privileged.api` from Doze; keep Wireless Debugging on |
| `rish` prints `Permission denied` or `binder is null` | `head -n 20 "$PREFIX/bin/rish"` | `PKG` template token not replaced with `com.termux` or Shizuku stopped | Replace `PKG` with `com.termux`, start Shizuku, approve Termux in Shizuku |
| ACC fails to stop charging past 60% | `acc -t` and `acc -i` | Auto-selected kernel switch unsupported on this PMIC | Run `acc -t` to find working switch and pin it with `acc -s s="..."` |
| All internet dies after enabling AFWall+ | `iptables -S OUTPUT` | `[0] root` / `netd` blocked in Whitelist mode or missing IPv6 rules | Allow `[0] root` and `(kernel)` in AFWall+, enable IPv6 support |
| Root script fails with `Permission denied` | `dmesg \| grep 'avc: denied'` | Wrong SELinux context on binary/script | Run `restorecon` or `chcon` to match expected context |

## Recover from a Root Module Bootloop

Use these escalation steps in order—none of them wipe your `/data` user files.

### Method 1: Hardware Safe Mode (No PC Needed)

- **Magisk:** Force reboot; as soon as the boot animation appears, press and hold **Volume Down** until Android boots into **Safe Mode**. Magisk detects Safe Mode and automatically disables every module in `/data/adb/modules/*` (creates a `disable` file inside each). Reboot normally and uninstall the offending module.
- **KernelSU:** While the device is booting, press **Volume Down** 3 times quickly (within the early boot window) to enter KernelSU Safe Mode, which disables all modules automatically.

### Method 2: Early-Boot ADB Module Removal

If `adbd` comes up briefly before SystemUI crashes:

`[NON-ROOT]` (Host workstation via ADB) `[REBOOT]`

```bash
# Magisk: remove all modules cleanly and reboot automatically
adb wait-for-device shell magisk --remove-modules

# Or disable only one suspected module if root shell is available
adb wait-for-device shell su -c 'touch /data/adb/modules/<bad-module-id>/disable && reboot'
```

### Method 3: Fastboot Stock Boot Override

If ADB never initializes, flash the unmodified stock `init_boot.img` (or `boot.img`) via Fastboot—this boots stock Android without root so you can inspect backups or switch to the intact A/B slot:

`[NON-ROOT]` `[REBOOT]`

```bash
fastboot flash init_boot ./stock_init_boot.img
fastboot reboot
```

## Fix Wrong Partition Flashed (boot vs init_boot)

If you flashed a Magisk-patched `boot.img` onto an Android 13+ GKI device that actually uses `init_boot`:

`[DESTRUCTIVE]` `[REBOOT]`

```bash
# 1. Restore unmodified stock boot.img first
fastboot flash boot ./stock_boot.img

# 2. Flash the properly patched init_boot.img
fastboot flash init_boot ./magisk_patched_init_boot.img
fastboot reboot
```

> **Watch out:** Never mix a Magisk-patched `init_boot.img` with a KernelSU-patched `boot.img` on the same slot simultaneously. Conflicting `su` daemons and overlay mounts cause unpredictable crashes and silent module failures. Remove one completely (restore stock image) before installing the other.

## Fix Shizuku and rish Connection Failures

`[NON-ROOT]` (Termux shell)

```bash
# Verify rish binary and dex exist side-by-side and PKG is substituted properly
ls -la "$PREFIX/bin/rish" "$PREFIX/bin/rish_shizuku.dex"
grep 'APPLICATION_ID' "$PREFIX/bin/rish"

# Test basic invocation and inspect stderr
rish -c 'id'
```

Common causes and fixes:
- `Shizuku service is not running`: Open Shizuku app and restart via Wireless Debugging.
- `java.lang.SecurityException` / authorization denied: Open Shizuku -> **Authorized applications** -> toggle **Termux** on.
- Shizuku dies on Xiaomi/Realme/Oppo: Disable **MIUI Optimization** or enable **Autostart** + **No restrictions** battery policy for Shizuku, and ensure **USB debugging (Security settings)** is enabled.

## Debug ACC Charging Switch and Idle Mode Failures

If `acc -i` shows the phone continuing to charge past `pc=60` or cycling violently every 5 seconds:

`[ROOT]`

```bash
# 1. Check whether accd daemon is actually running
accd -i
# Start daemon if stopped
accd

# 2. Dump full switch test results while connected to your charger
acc -t

# 3. Inspect active configuration file for conflicting overrides
cat /data/adb/vr25/acc-data/config.txt | grep -v '^#' | grep -v '^$'

# 4. If hardware lacks true bypass (battIdleMode=false), widen hysteresis band to reduce wear
acc -s pc=65 rc=45 prioritize_batt_idle_mode=false
```

> **Watch out:** Some USB-C PD chargers reset and renegotiate power delivery every time a kernel charging switch toggles `input_suspend`, causing an audible charging chime loop and screen wakeups. Test with a plain 5V/2A USB-A charger or try an alternate switch from `acc -t` (such as `charging_enabled` or `battery/charge_control_limit`) before deploying unattended.

## Recover from AFWall+ Network Lockout

If a misconfigured AFWall+ rule locks out DNS, Wi-Fi, or SSH over LAN:

`[ROOT]` (via USB `adb shell su` or on-device terminal)

```bash
# Flush custom AFWall+ filter chains immediately to restore connectivity
iptables -F afwall 2>/dev/null
iptables -F afwall-wifi 2>/dev/null
iptables -F afwall-3g 2>/dev/null
ip6tables -F afwall 2>/dev/null
ip6tables -F afwall-wifi 2>/dev/null
ip6tables -F afwall-3g 2>/dev/null

# Verify default OUTPUT policy is ACCEPT
iptables -P OUTPUT ACCEPT
ip6tables -P OUTPUT ACCEPT
```

Then open AFWall+, verify `[0] (root)` and `(kernel)` are checked, and re-apply rules cleanly.

## Diagnose SELinux AVC Denials

`[ROOT]`

```bash
# Stream live SELinux denials while reproducing a failing script or service
dmesg -w | grep --line-buffered 'avc: denied'

# Check active contexts of a failing process and target file
ps -AZ | grep -E 'accd|sshd|termux'
ls -Z /data/adb/service.d/

# Temporary 60-second diagnostic verification ONLY (never leave permissive):
# setenforce 0 && <test command> && setenforce 1
```
