# Termux Pocket Linux Server Bootstrap

Deploying a persistent headless Linux server on spare Android hardware using F-Droid Termux, OpenSSH (port 8022), `Termux:Boot`, and Android 12+ background-survival settings.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Install Termux and Add-Ons from F-Droid](#install-termux-and-add-ons-from-f-droid)
- [Switch Mirrors and Upgrade Base Packages](#switch-mirrors-and-upgrade-base-packages)
- [Configure Storage Access and Base Tooling](#configure-storage-access-and-base-tooling)
- [Set Up OpenSSH Server on Port 8022](#set-up-openssh-server-on-port-8022)
- [Disable Android 12+ Phantom Process Killer and Doze](#disable-android-12-phantom-process-killer-and-doze)
- [Configure Autostart via Termux:Boot](#configure-autostart-via-termuxboot)

## Install Termux and Add-Ons from F-Droid

Install Termux and all companion apps strictly from **F-Droid** or the official **GitHub Releases** (signed with the same signing key).

| Package | Source | Purpose |
| --- | --- | --- |
| `com.termux` | F-Droid / GitHub Releases | Core terminal emulator and Debian-derived package environment |
| `com.termux.boot` | F-Droid / GitHub Releases | Executes `~/.termux/boot/*` scripts automatically after Android boots |
| `com.termux.api` | F-Droid / GitHub Releases | Exposes battery telemetry, Wi-Fi state, and notifications to CLI scripts |

> **Watch out:** Never install Termux from the Google Play Store. The Play Store build is deprecated, targets a restricted Android SDK version that breaks executable permissions (`W^X` / `execve` restrictions), ships broken repository URLs, and uses a different APK signing key that prevents `Termux:Boot` and `Termux:API` from F-Droid from installing alongside it (`INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`).

After installing `Termux:Boot`, open the **Termux:Boot** app once from the Android launcher so Android registers its `BOOT_COMPLETED` broadcast receiver, then exit it.

## Switch Mirrors and Upgrade Base Packages

Launch Termux on the device and select a fast mirror group before upgrading packages.

`[NON-ROOT]` (Termux shell)

```bash
# Interactive mirror selector — choose a regional mirror group or Cloudflare/Grimler mirror
termux-change-repo

# Update package index and upgrade all preinstalled packages (accept maintainer configs with 'Y' on fresh installs)
pkg update -y && pkg upgrade -y
```

## Configure Storage Access and Base Tooling

Grant access to shared Android storage (`/sdcard` mapped into `~/storage/`) and install core server administration packages.

`[NON-ROOT]` (Termux shell)

```bash
# Prompts Android runtime permission dialog; creates ~/storage/{shared,downloads,dcim,movies,music}
termux-setup-storage

# Install core pocket-server package set
pkg install -y \
  openssh \
  termux-services \
  termux-api \
  proot-distro \
  tmux \
  git \
  curl \
  rsync \
  jq \
  htop \
  iproute2 \
  dnsutils \
  procps \
  cronie
```

Restart the Termux app completely after installing `termux-services` so the `$PREFIX/etc/profile.d/start-services.sh` hook initializes `runsvdir`.

## Set Up OpenSSH Server on Port 8022

Android prohibits unprivileged apps from binding TCP ports below `1024`, so Termux `sshd` listens on port **8022** by default.

### 1. Provision Your Workstation Ed25519 Public Key

On your workstation (`[NON-ROOT]`):

```bash
# Generate a dedicated Ed25519 keypair if you do not already have one
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_termux -C "admin@workstation"
cat ~/.ssh/id_ed25519_termux.pub
```

Push the public key to the device over ADB (faster and less error-prone than typing on a phone keyboard):

`[NON-ROOT]` (Host workstation via ADB)

```bash
adb push ~/.ssh/id_ed25519_termux.pub /sdcard/Download/authorized_key.pub
```

### 2. Configure Key-Only Auth and Start `sshd`

In Termux (`[NON-ROOT]`):

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cat ~/storage/downloads/authorized_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
rm -f ~/storage/downloads/authorized_key.pub

# Lock sshd to key-only authentication on port 8022
cat > "$PREFIX/etc/ssh/sshd_config" <<'EOF'
Port 8022
PrintMotd yes
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
Subsystem sftp /data/data/com.termux/files/usr/libexec/sftp-server
EOF

# Enable sshd under termux-services (runit) or start directly
sv-enable sshd
sv status sshd

# Verify active listener and local IP
ss -tlnp | grep 8022
ip -4 -o addr show wlan0
```

Test from your workstation (`[NON-ROOT]`):

```bash
# Termux ignores the SSH username (maps to the Termux app UID), but pass any label such as 'termux'
ssh -i ~/.ssh/id_ed25519_termux -p 8022 termux@192.168.1.42
```

## Disable Android 12+ Phantom Process Killer and Doze

Android 12+ enforces a hard system-wide cap of **32 forked child processes** (`max_phantom_processes`) across background apps. Running `proot-distro`, `sshd`, `runit`, compilers, or Node/Python workers quickly exceeds 32 child processes and gets terminated abruptly with `[Process completed (signal 9)]`.

Run these commands once from your host workstation via ADB (no root required):

`[NON-ROOT]` (Host workstation via ADB)

```bash
# 1. Prevent Google Play Services / Phenotype from resetting device_config flags back to defaults
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent"

# 2. Raise phantom process cap from 32 to INT_MAX
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"

# 3. Disable phantom process monitoring toggle (Android 12L / 13 / 14+)
adb shell settings put global settings_enable_monitor_phantom_procs false

# 4. Exempt Termux and Termux:Boot from Android Doze battery restrictions
adb shell dumpsys deviceidle whitelist +com.termux
adb shell dumpsys deviceidle whitelist +com.termux.boot

# 5. Verify both settings took effect
adb shell "/system/bin/device_config get activity_manager max_phantom_processes"
adb shell dumpsys deviceidle whitelist | grep com.termux
```

> **Watch out:** On Android 12 (initial release before 12L), the `set_sync_disabled_for_tests persistent` flag does not exist on early builds; use `until_reboot` or re-apply via Wireless ADB / Shizuku after OS reboots. On OEM skins (Xiaomi HyperOS, Samsung One UI, OnePlus OxygenOS), you must also manually set **App Info -> Battery -> Unrestricted** and enable **Autostart** in OEM Settings.

## Configure Autostart via Termux:Boot

Create an executable boot script in `~/.termux/boot/` that acquires a partial CPU wake-lock, starts `runsvdir` (`termux-services`), and guarantees `sshd` comes online after power loss without manual unlocking.

`[NON-ROOT]` (Termux shell)

```bash
mkdir -p ~/.termux/boot

cat > ~/.termux/boot/00-start-server.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Acquire CPU wake-lock so Android does not suspend background daemons when screen turns off
termux-wake-lock

# Start termux-services supervisor (manages sshd, cloudflared, crond, and custom runit services)
export SVDIR="$PREFIX/var/service"
if ! pgrep -f "runsvdir" >/dev/null 2>&1; then
  nohup runsvdir -P "$SVDIR" </dev/null >/dev/null 2>&1 &
fi

# Fallback: ensure sshd is listening even if termux-services has not started it yet
sleep 2
pgrep -x sshd >/dev/null 2>&1 || sshd
EOF

chmod 700 ~/.termux/boot/00-start-server.sh
```

Reboot the phone, wait 30–60 seconds after the lock screen appears (Android must complete boot and unlock credential-encrypted storage—if you set a PIN/password, note that Android File-Based Encryption blocks `Termux:Boot` from reading `~/.termux/boot/` until the first unlock after reboot), then verify SSH connectivity.
