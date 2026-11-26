# Elevated Android Ops Bootstrap (Shizuku, Root & ACC)

Bootstrapping non-root `uid=2000` privileged operations with Shizuku/`rish`, deciding between Magisk, KernelSU, and APatch for `boot`/`init_boot` rooting, and configuring ACC to protect 24/7 plugged-in phone server batteries.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Choose Privilege Tier: Shizuku vs Root](#choose-privilege-tier-shizuku-vs-root)
- [Bootstrap Shizuku via Wireless Debugging](#bootstrap-shizuku-via-wireless-debugging)
- [Configure rish Shell Inside Termux](#configure-rish-shell-inside-termux)
- [Bootstrap Root: Magisk vs KernelSU vs APatch](#bootstrap-root-magisk-vs-kernelsu-vs-apatch)
- [Identify boot vs init_boot Before Patching](#identify-boot-vs-init_boot-before-patching)
- [Install and Configure ACC for 24/7 Charging Safety](#install-and-configure-acc-for-247-charging-safety)

## Choose Privilege Tier: Shizuku vs Root

Do not unlock the bootloader or root a device if `uid=2000` (`shell`) privileges already cover your operational requirements.

| Requirement | Shizuku (`uid=2000`, No Root) | Root (`uid=0`, Magisk / KernelSU / APatch) |
| --- | --- | --- |
| Debloat (`pm uninstall --user 0`), Canta, Hail | Supported | Supported |
| App Ops background/permission enforcement | Supported | Supported |
| Run `device_config` (disable Phantom Process Killer) | Supported via `rish` | Supported |
| Bootloader stays locked / Verified Boot intact | Yes | No (unlocked bootloader required) |
| Hardware charging cutoff / idle bypass (ACC) | Not possible | Supported (sysfs `/sys/class/power_supply/*`) |
| Native `iptables`/`nftables` & AFWall+ per-UID firewall | Not possible | Supported |
| Raw `tcpdump`, mounting filesystems, kernel tuning | Not possible | Supported |

## Bootstrap Shizuku via Wireless Debugging

Shizuku spawns a privileged `uid=2000` Binder proxy service without modifying `/system` or unlocking the bootloader.

1. Install **Shizuku** from GitHub Releases or Google Play (`moe.shizuku.privileged.api`).
2. Enable **Developer options -> Wireless debugging** on Android 11+.
3. Open **Shizuku -> Start via Wireless debugging -> Pairing**.
4. Tap **Notification options** if prompted, then open **Developer options -> Wireless debugging -> Pair device with pairing code** and enter the 6-digit code in the Shizuku notification.
5. Return to Shizuku and tap **Start**. Status changes to `Shizuku is running (adb)`.

### Alternative: Start Shizuku via USB ADB (Android 8–10 or No Wi-Fi)

`[NON-ROOT]` (Host workstation via ADB)

```bash
adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh
```

> **Watch out:** Non-root Shizuku does not survive device reboots; after any reboot you must start it again via Wireless Debugging (takes ~5 seconds on-device without a PC) or USB ADB. Turning off **Wireless debugging** after Shizuku has started stops the Shizuku service on some Android 13/14 OEM builds (notably Xiaomi HyperOS)—keep Wireless Debugging enabled or test behavior on your ROM.

## Configure rish Shell Inside Termux

`rish` lets you execute `uid=2000` (`shell`) commands directly inside Termux on the phone with zero PC attached.

1. Open the **Shizuku** app -> **Use Shizuku in terminal apps** -> **Export files** -> choose `/sdcard/Download/rish/`.
2. Copy `rish` and `rish_shizuku.dex` into Termux `$PREFIX/bin` and bind the application ID to `com.termux`:

`[NON-ROOT]` (Termux shell)

```bash
cp ~/storage/downloads/rish/rish "$PREFIX/bin/rish"
cp ~/storage/downloads/rish/rish_shizuku.dex "$PREFIX/bin/rish_shizuku.dex"
chmod 700 "$PREFIX/bin/rish"

# Set PKG to com.termux so Shizuku accepts Binder requests from Termux
sed -i 's/PKG/com.termux/g' "$PREFIX/bin/rish"

# Verify uid=2000 shell access directly from Termux
rish -c 'id && /system/bin/device_config get activity_manager max_phantom_processes'
```

Expected output shows `uid=2000(shell) gid=2000(shell)`.

## Bootstrap Root: Magisk vs KernelSU vs APatch

| Solution | Injection Layer | Best Fit | Key Characteristics |
| --- | --- | --- | --- |
| **Magisk** | Userspace (`init` + `ramdisk` patch in `boot`/`init_boot`) | Broadest device compatibility (Android 6–15, GKI and legacy non-GKI kernels) | Mature ecosystem, built-in Zygisk, DenyList, huge module base |
| **KernelSU** | Kernel-space (GKI 2.0 `android12-5.10+` LKM or compiled kernel) | Modern GKI devices needing cleaner root isolation & allowlist-by-default | Apps cannot see `su` unless explicitly granted; supports LKM patching on `init_boot`/`boot` |
| **APatch** | Kernel binary patch (`kimg` / KernelPatch) on ARM64 Linux 3.18–6.1+ | Non-GKI devices wanting kernel-level root (KPModules + Android modules) | Patches kernel inside `boot.img` directly; requires SuperKey passphrase |

## Identify boot vs init_boot Before Patching

Android 13+ devices launching with Generic Kernel Image (GKI 2.0) moved the generic ramdisk out of `boot.img` into a dedicated `init_boot.img` partition. Patching the wrong image either yields no root or triggers a bootloop.

`[NON-ROOT]` (Host workstation via Fastboot or ADB)

```bash
# Check kernel version (GKI format: 5.10.x-android12 / 5.15.x-android13 / 6.1.x-android14)
adb shell uname -r

# Check whether init_boot partition exists on the device
adb reboot bootloader
fastboot getvar partition-size:init_boot_a
fastboot getvar partition-size:boot_a
```

- **Magisk / KernelSU LKM:** If `init_boot_a` exists and is non-zero (typically 8 MB), extract and patch **`init_boot.img`** from the exact factory firmware build matching `ro.build.fingerprint`. If `init_boot` does not exist, patch **`boot.img`**.
- **APatch / KernelSU GKI kernel-image replace:** Always patches the kernel inside **`boot.img`** (never `init_boot.img`).

### Safe Patch-and-Flash Workflow (Magisk Example)

`[NON-ROOT]` -> `[DESTRUCTIVE]` `[REBOOT]`

```bash
# 1. Push stock init_boot.img (or boot.img) matching current OS build to device
adb push ./stock_init_boot.img /sdcard/Download/

# 2. In Magisk Manager on device: Install -> Select and Patch a File -> select stock_init_boot.img
# 3. Pull patched image back to host
adb pull /sdcard/Download/magisk_patched-*.img ./patched_init_boot.img

# 4. Boot into Fastboot and TEST IN RAM FIRST (if supported by bootloader)
adb reboot bootloader
fastboot boot ./patched_init_boot.img

# 5. Once booted cleanly and root verified, flash permanently to active slot
adb reboot bootloader
fastboot flash init_boot ./patched_init_boot.img
fastboot reboot
```

> **Watch out:** Never flash a `boot.img` or `init_boot.img` extracted from a different security patch month or regional build than the OS currently installed on the phone. Mismatched kernel/ramdisk modules cause Wi-Fi, touchscreen, or vendor HAL failures and bootloops. Always keep a local copy of the exact unmodified stock image on your workstation.

## Install and Configure ACC for 24/7 Charging Safety

Phones plugged into AC power 24/7 at 100% state-of-charge (4.35–4.45 V per cell) suffer accelerated lithium-ion degradation and physical battery swelling within 6–12 months. **ACC (Advanced Charging Controller)** enforces hardware charging cutoffs and bypass/idle charging via kernel power-supply sysfs controls.

### 1. Install ACC Module (`[ROOT]`)

Download the latest ACC release ZIP (`acc_*.zip`) from GitHub (`VR-25/acc`), install via Magisk/KernelSU/APatch Manager, and reboot (`[REBOOT]`).

### 2. Configure 50–60% Server Charge Band and Idle Mode

`[ROOT]` (Root shell via `adb shell su` or Termux `su`)

```bash
# Test which kernel charging switches work cleanly and whether battery idle (bypass) mode is supported
acc -t

# Configure 24/7 server baseline:
#   pc=60 (pause charging at 60%)
#   rc=50 (resume charging only if battery drops to 50%)
#   ct=40 (pause charging if battery temperature reaches 40 C)
#   rt=35 (resume charging once temperature cools to 35 C)
#   pbm=true (prioritize battery idle / bypass power directly from USB when available)
acc -s pc=60 rc=50 ct=40 rt=35 prioritize_batt_idle_mode=true

# Inspect live daemon status, active switch, voltage, current (mA), and temperature
acc -i
```
