# ADB & Fastboot Bootstrap

Host workstation installation, Linux udev rules, USB and Wireless ADB pairing, and Fastboot verification for managing Android devices over command line.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Prerequisites](#prerequisites)
- [Install Android Platform-Tools](#install-android-platform-tools)
- [Configure Linux udev Rules](#configure-linux-udev-rules)
- [Configure Windows USB Drivers](#configure-windows-usb-drivers)
- [Enable USB Debugging and Authorize Host](#enable-usb-debugging-and-authorize-host)
- [Configure Wireless ADB](#configure-wireless-adb)
- [Verify Fastboot Connectivity](#verify-fastboot-connectivity)

## Prerequisites

| Requirement | Minimum Specification | Notes |
| --- | --- | --- |
| Android OS | Android 11+ for native `adb pair` | Android 8–10 requires USB bootstrap via `adb tcpip 5555` |
| USB Cable | Data-capable USB-C / USB-A | Charge-only cables fail silently without enumerating USB descriptors |
| Host Platform-Tools | r34.0.0 or newer | Required for modern `fastboot`, `adb pair`, and A/B slot commands |
| Network (Wireless ADB) | Same L2 subnet, no AP client isolation | Host and device must reach ephemeral TCP ports directly |

## Install Android Platform-Tools

Prefer Google's official Platform-Tools release over outdated distribution packages; older `fastboot` binaries fail on dynamic partitions (`super`) and A/B slot metadata.

### Linux (Official Archive — Recommended)

`[ROOT]` (if installing to `/opt`) or `[NON-ROOT]` (installing to `~/.local`)

```bash
curl -fsSL -o /tmp/platform-tools.zip https://dl.google.com/android/repository/platform-tools-latest-linux.zip
mkdir -p "$HOME/.local/share"
unzip -q -o /tmp/platform-tools.zip -d "$HOME/.local/share"
rm -f /tmp/platform-tools.zip

# Add to ~/.bashrc or ~/.zshrc
echo 'export PATH="$HOME/.local/share/platform-tools:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.local/share/platform-tools:$PATH"

adb --version
fastboot --version
```

### Linux (Distribution Packages)

`[ROOT]`

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y android-sdk-platform-tools android-sdk-platform-tools-common

# Fedora / RHEL (EPEL)
sudo dnf install -y android-tools

# Arch Linux
sudo pacman -S --needed android-tools android-udev
```

### macOS

`[NON-ROOT]`

```bash
brew install --cask android-platform-tools
adb --version
fastboot --version
```

### Windows

`[NON-ROOT]` (PowerShell)

```powershell
# Using winget
winget install --id Google.PlatformTools -e

# Or using scoop
scoop install adb

adb --version
fastboot --version
```

> **Watch out:** Running two different versions of `adb` on the same host (for example, `/usr/bin/adb` from apt alongside Android Studio's SDK `platform-tools/adb`) causes repeated `adb server version (XX) doesn't match this client (YY); killing...` loops and drops active shell sessions. Keep a single `adb` binary in `PATH`.

## Configure Linux udev Rules

Without `udev` rules, non-root users receive `no permissions (user in plugdev group; are your udev rules wrong?)` when querying `adb devices` or `fastboot devices`.

`[ROOT]`

```bash
# Install community-maintained vendor ID rules (covers Google, Samsung, Xiaomi, OnePlus, Motorola, Sony, etc.)
sudo curl -fsSL -o /etc/udev/rules.d/51-android.rules \
  https://raw.githubusercontent.com/M0Rf30/android-udev-rules/main/51-android.rules
sudo chmod a+r /etc/udev/rules.d/51-android.rules

# Create adbusers/plugdev group membership for current user
sudo groupadd -f adbusers
sudo usermod -aG adbusers,plugdev "$USER"

# Reload udev rules without rebooting
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Log out and back in (or run `newgrp plugdev`) for group membership changes to take effect in your shell, then unplug and reconnect the USB cable.

### Verify USB Enumeration

`[NON-ROOT]`

```bash
lsusb | grep -iE 'google|samsung|xiaomi|oneplus|qualcomm|motorola|mediatek|android'
```

## Configure Windows USB Drivers

Windows requires distinct kernel drivers for ADB mode and Fastboot (bootloader) mode. ADB working does not guarantee Fastboot will enumerate.

1. Download the official Google USB Driver (`latest_usb_driver_windows.zip`) or OEM-specific driver (Samsung Android USB Driver, Motorola Device Manager, Xiaomi USB Driver).
2. Boot the device into Fastboot (`adb reboot bootloader`).
3. Open **Device Manager** (`devmgmt.msc`) and look under **Other devices** for `Android` or `Fastboot` with a warning icon.
4. Right-click -> **Update driver** -> **Browse my computer** -> **Let me pick from a list** -> **Android Device** -> **Android Bootloader Interface**.

`[ROOT]` (Elevated PowerShell — verify driver binding)

```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -match 'Android|ADB|Fastboot' } |
  Format-Table Status, Class, FriendlyName, InstanceId -AutoSize
```

## Enable USB Debugging and Authorize Host

1. On the device: **Settings -> About phone -> Build number** (tap 7 times until Developer Options activates).
2. Open **Settings -> System -> Developer options**.
3. Enable **USB debugging**.
4. Optional for unattended servers or headless rigs: enable **Stay awake** (keeps screen on while charging) and **Disable adb authorization timeout** (Android 11+, prevents 7-day RSA key expiry).
5. Connect the device via USB and trigger the RSA fingerprint prompt:

`[NON-ROOT]`

```bash
adb start-server
adb devices -l
```

Accept the **Allow USB debugging** dialog on the device screen and check **Always allow from this computer**. Host RSA keys are generated and stored at `~/.android/adbkey` (private) and `~/.android/adbkey.pub` (public).

Expected healthy output:

```text
List of devices attached
1A2B3C4D5E6F           device usb:1-2 product:panther model:Pixel_7 device:panther transport_id:1
```

## Configure Wireless ADB

### Android 11+ Native Pairing (No USB Required)

1. Connect host and device to the same Wi-Fi network.
2. On the device: **Developer options -> Wireless debugging** (toggle on).
3. Tap **Pair device with pairing code**. Note the IP, pairing port (not the main connection port), and 6-digit code.
4. Pair from the host, then connect to the main IP and port shown on the Wireless debugging screen:

`[NON-ROOT]`

```bash
# Step 1: One-time cryptographic pairing (uses the ephemeral pairing port)
adb pair 192.168.1.42:37891
# Enter pairing code when prompted

# Step 2: Connect to the active Wireless debugging daemon port
adb connect 192.168.1.42:41205

# Verify connection
adb devices -l
```

### Legacy TCP/IP Mode (Android 8–10 or Fixed Port 5555)

Requires an initial USB connection; persists until the device reboots.

`[NON-ROOT]`

```bash
# Switch adbd on the USB-connected device to listen on TCP port 5555
adb tcpip 5555

# Find the device's Wi-Fi IP address
adb shell ip -4 -o addr show wlan0

# Unplug USB and connect over Wi-Fi
adb connect 192.168.1.42:5555
```

> **Watch out:** `adb tcpip 5555` binds the ADB daemon to `0.0.0.0:5555` on all interfaces without an ephemeral port rotation. Never leave TCP port 5555 open on untrusted public Wi-Fi or corporate guest networks; switch back immediately with `adb usb` when finished.

## Verify Fastboot Connectivity

Fastboot runs inside the bootloader before the Android kernel boots. ADB commands do not work in Fastboot mode, and Fastboot commands do not work in booted Android.

`[NON-ROOT]` `[REBOOT]`

```bash
# Reboot from booted Android into the bootloader
adb reboot bootloader

# Confirm host detects device in Fastboot mode
fastboot devices

# Query key bootloader state variables (read-only)
fastboot getvar product
fastboot getvar unlocked
fastboot getvar current-slot
fastboot getvar is-userspace

# Return to normal Android OS
fastboot reboot
```

If `fastboot devices` returns empty on Linux, verify `lsusb` shows the device and re-check `/etc/udev/rules.d/51-android.rules` for the bootloader USB PID (some vendors change USB Vendor/Product IDs between ADB and Fastboot modes).
