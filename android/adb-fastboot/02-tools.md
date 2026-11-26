# ADB & Fastboot Toolbelt

Reference matrix, installation commands, production flags, and failure modes for core Android device management, display mirroring, telemetry, and flashing tools.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Tool Matrix](#tool-matrix)
- [adb](#adb)
- [fastboot](#fastboot)
- [scrcpy](#scrcpy)
- [dumpsys](#dumpsys)
- [logcat](#logcat)
- [pm and cmd package](#pm-and-cmd-package)
- [aapt2](#aapt2)

## Tool Matrix

| Tool | Runs On | Primary Use Case | Privileges Required |
| --- | --- | --- | --- |
| `adb` | Host | Shell execution, file transfer, port forwarding, APK install | Host `[NON-ROOT]`, device `uid=2000` (`shell`) |
| `fastboot` | Host | Bootloader queries, A/B slot switching, partition flashing | Host `[NON-ROOT]` (with udev), unlocked bootloader for writes |
| `scrcpy` | Host | Low-latency screen mirroring, headless control, OTG HID input | Host `[NON-ROOT]`, USB/Wireless ADB (none for `--otg`) |
| `dumpsys` | Device (`adb shell`) | Live system service telemetry (battery, thermal, memory, network) | Device `shell` (`uid=2000`) |
| `logcat` | Device (`adb logcat`) | Real-time and buffered Android ring-buffer log inspection | Device `shell` (`uid=2000`) |
| `pm` / `cmd package` | Device (`adb shell`) | Package enumeration, user-0 debloat, permission grants | Device `shell` (`uid=2000`) |
| `aapt2` | Host | Static APK manifest, package ID, ABI, and permission inspection | Host `[NON-ROOT]` |

## adb

Android Debug Bridge client/server daemon for communicating with booted Android and recovery environments.

### Install

`[ROOT]` (Linux packages) or `[NON-ROOT]` (macOS/Windows)

```bash
# Debian / Ubuntu
sudo apt install -y android-sdk-platform-tools

# Arch Linux
sudo pacman -S --needed android-tools

# macOS
brew install --cask android-platform-tools

# Windows (winget)
winget install --id Google.PlatformTools -e
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Target a specific device by serial when multiple devices/emulators are attached
adb -s 1A2B3C4D5E6F shell getprop ro.build.fingerprint

# Transfer files with timestamp preservation and progress
adb push -a ./backup.tar.zst /sdcard/Download/
adb pull -a /sdcard/DCIM/Camera/ ./camera-backup/

# Install split APKs (App Bundles) atomically, allowing downgrade and granting runtime permissions
adb install-multiple -r -d -g base.apk split_config.arm64_v8a.apk split_config.en.apk

# Stream raw binary stdout without PTY CRLF line-ending corruption
adb exec-out screencap -p > screen.png
```

> **Watch out:** Running `adb shell screencap -p > screen.png` instead of `adb exec-out screencap -p > screen.png` silently corrupts binary streams on older ADB implementations because `adb shell` allocates a pseudo-terminal that converts `\n` (`0x0A`) to `\r\n` (`0x0D 0x0A`). Always use `adb exec-out` for binary pipes (`tar`, `screencap`, `dd`).

## fastboot

Low-level bootloader protocol client for partition flashing, kernel testing, and A/B slot administration.

### Install

Bundled with `android-platform-tools` / `android-tools` (see `adb` installation above).

### Real-World Usage

`[NON-ROOT]` (host) / `[DESTRUCTIVE]` (for `flash` and `erase`) / `[REBOOT]`

```bash
# Dump all bootloader metadata variables (partition sizes, slot status, secure boot state)
fastboot getvar all

# Inspect active A/B slot and switch active slot without flashing
fastboot getvar current-slot
fastboot --set-active=b

# Boot a kernel/recovery/patched boot image ONCE from RAM without modifying flash storage
fastboot boot ./magisk_patched_init_boot.img

# Flash an image to a specific partition on the currently active slot
fastboot flash init_boot ./magisk_patched_init_boot.img
```

> **Watch out:** On Android 10+ devices with dynamic partitions, certain partitions (`system`, `vendor`, `product`) live inside the `super` partition and cannot be flashed from the hardware bootloader. You must run `fastboot reboot fastboot` to enter **fastbootd** (userspace fastboot, confirmed by `fastboot getvar is-userspace` returning `yes`) before flashing dynamic logical partitions.

## scrcpy

High-performance H.264/H.265/AV1 display mirroring and input forwarding tool using an ephemeral on-device server pushed over ADB.

### Install

`[ROOT]` (Linux) or `[NON-ROOT]` (macOS/Windows)

```bash
# Debian / Ubuntu (note: distro repo version is often old; verify scrcpy --version >= 2.4)
sudo apt install -y scrcpy

# Arch Linux
sudo pacman -S --needed scrcpy

# macOS
brew install scrcpy

# Windows
winget install --id Genymobile.scrcpy -e
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Server/kiosk control: turn physical screen off, prevent sleep, disable audio, cap resolution & bitrate
scrcpy --turn-screen-off --stay-awake --no-audio --max-size=1024 --video-bit-rate=2M

# High-efficiency HEVC stream over Wireless ADB with low frame rate cap for remote admin
scrcpy --tcpip=192.168.1.42:5555 --video-codec=h265 --max-fps=15 --max-size=960 --no-audio

# OTG physical USB HID mode (keyboard + mouse without USB debugging enabled — broken screen recovery)
scrcpy --otg

# Record device display and audio directly to host MP4 without showing a mirror window
scrcpy --no-window --record=session.mp4 --max-size=1280
```

> **Watch out:** Android blocks screen capture on apps that set `WindowManager.LayoutParams.FLAG_SECURE` (banking apps, password managers, DRM video, lock screen PIN overlays), rendering a solid black frame in `scrcpy`. This is enforced by SurfaceFlinger on non-rooted devices and cannot be bypassed via `scrcpy` flags.

## dumpsys

On-device Binder IPC diagnostic utility that queries internal state from every registered Android system service.

### Install

Preinstalled on all Android devices at `/system/bin/dumpsys`. Invoke via `adb shell dumpsys`.

### Real-World Usage

`[NON-ROOT]`

```bash
# Battery charge level, health, voltage, temperature (tenths of a degree C), and power source
adb shell dumpsys battery

# Thermal mitigation status, skin/CPU/battery sensors, and active throttling levels
adb shell dumpsys thermalservice

# Detailed RAM breakdown (PSS, RSS, swap) for a specific app or full system summary
adb shell dumpsys meminfo com.termux
adb shell dumpsys meminfo --package

# Network traffic stats, Doze/App Standby idle whitelist, and foreground activity inspection
adb shell dumpsys netstats detail | head -n 60
adb shell dumpsys deviceidle whitelist
adb shell dumpsys activity top | grep -E 'ACTIVITY|mResumed'
adb shell dumpsys package com.termux | grep -E 'versionName|userId|granted=true'
```

> **Watch out:** `dumpsys` output schemas are not stable across Android API levels or OEM forks (Samsung One UI and Xiaomi HyperOS rename or wrap fields in `thermalservice` and `battery`). Always inspect raw output before hardcoding `awk`/`grep` parsers in monitoring scripts.

## logcat

Reads Android's kernel-backed `logd` circular buffers (`main`, `system`, `crash`, `events`, `radio`).

### Install

Preinstalled on all Android devices; invoke from host via `adb logcat`.

### Real-World Usage

`[NON-ROOT]`

```bash
# Dump existing crash buffer non-interactively and exit (-d = dump, -b crash = crash ring buffer)
adb logcat -d -b crash -v threadtime

# Silence verbose noise (*:S) and show only Errors/Fatals globally (*:E) or specific tags at Debug+
adb logcat -v color '*:E'
adb logcat -v time AndroidRuntime:E ActivityManager:W '*:S'

# Follow logs scoped strictly to a running application's PID
adb logcat --pid="$(adb shell pidof -s com.termux)" -v threadtime

# Clear old ring buffers before reproducing a failure, then capture timestamped output to disk
adb logcat -c && adb logcat -v epoch,uid,threadtime -b main,system,crash > repro.log
```

> **Watch out:** On Linux/macOS shells (especially `zsh`), unquoted `*:E` or `*:S` triggers shell glob expansion against files in the current directory. Always single-quote filter expressions (`'*:E'`, `'*:S'`). Additionally, the `main` buffer wraps quickly on busy devices; increase buffer size in Developer Options -> Logger buffer sizes (or `adb logcat -G 16M`) during long captures.

## pm and cmd package

Android Package Manager CLI for enumerating, disabling, uninstalling for `user 0`, restoring, and auditing installed packages without root.

### Install

Preinstalled on all Android devices (`/system/bin/pm` and `/system/bin/cmd`).

### Real-World Usage

`[NON-ROOT]`

```bash
# List packages: -3 third-party, -s system, -d disabled, -u include uninstalled-for-user-0, -f show APK path
adb shell pm list packages -s -f | sort
adb shell pm list packages -u | grep -i facebook

# Safely remove bloatware for the primary user (user 0) without modifying /system (APK stays on read-only partition)
adb shell pm uninstall -k --user 0 com.example.bloatware

# Non-destructive alternative: freeze package so it cannot launch or receive broadcasts
adb shell pm disable-user --user 0 com.example.bloatware

# Restore any system package previously removed via pm uninstall --user 0
adb shell cmd package install-existing com.example.bloatware
```

> **Watch out:** `pm uninstall --user 0` does not free `/system` or `/product` storage because those partitions are immutable (`erofs`/`ext4` read-only under dm-verity). Worse, uninstalling core OEM dependencies (such as `com.android.systemui`, carrier provisioning services, or Xiaomi `com.xiaomi.finddevice`) can trigger an immediate SystemUI crash loop requiring a factory reset. Always test with `pm disable-user --user 0` first when unsure.

## aapt2

Android Asset Packaging Tool for inspecting local APK binaries before sideloading.

### Install

`[ROOT]` (Linux) or `[NON-ROOT]` (via Android SDK Build-Tools)

```bash
# Debian / Ubuntu
sudo apt install -y aapt2

# Arch Linux (AUR) or Google Android SDK cmdline-tools
sdkmanager "build-tools;34.0.0"
```

### Real-World Usage

`[NON-ROOT]`

```bash
# Inspect package name, versionCode, targetSdkVersion, native ABIs, and requested permissions
aapt2 dump badging ./app-release.apk | grep -E 'package:|sdkVersion|targetSdkVersion|native-code|uses-permission'

# List all requested permissions cleanly
aapt2 dump permissions ./app-release.apk
```

> **Watch out:** Many modern apps are distributed as `.apkm`, `.xapk`, or `.apks` ZIP bundles containing split APKs rather than standalone `.apk` files. Unzip the archive first and inspect `base.apk` with `aapt2`, then install all required splits together via `adb install-multiple`.
