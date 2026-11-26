# Elevated Android Toolbelt (Shizuku, Root, ACC & Netfilter)

Tool matrix, installation methods, production CLI invocations, and edge-case warnings for Shizuku, Canta/Hail/App Ops, Magisk/KernelSU, ACC, AFWall+, `iptables`/`nftables`, and SELinux utilities.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Tool Matrix](#tool-matrix)
- [Shizuku and rish](#shizuku-and-rish)
- [Canta, Hail, and App Ops](#canta-hail-and-app-ops)
- [Magisk and ksud CLI](#magisk-and-ksud-cli)
- [ACC (Advanced Charging Controller)](#acc-advanced-charging-controller)
- [AFWall+ and Root iptables/nftables](#afwall-and-root-iptablesnftables)
- [SELinux Inspection Utilities](#selinux-inspection-utilities)

## Tool Matrix

| Tool | Privilege Tier | Install Source | Primary Use Case |
| --- | --- | --- | --- |
| Shizuku + `rish` | `[NON-ROOT]` (`uid=2000`) | GitHub / Play Store + Termux | On-device ADB-grade shell & Binder API broker |
| Canta / Hail / App Ops | `[NON-ROOT]` (via Shizuku) | F-Droid / IzzyOnDroid / GitHub | Safe UAD debloat, package freezing, granular permission ops |
| `magisk` / `ksud` | `[ROOT]` (`uid=0`) | Magisk / KernelSU Manager | Module management, Zygisk/DenyList control, safe-mode recovery |
| `acc` / `accd` | `[ROOT]` (`uid=0`) | GitHub (`VR-25/acc`) module | Charge percentage limits, thermal cutoffs, idle/bypass charging |
| AFWall+ / `iptables` / `nft` | `[ROOT]` (`uid=0`) | F-Droid / kernel netfilter | Per-UID egress firewall and packet filtering |
| `getenforce` / `chcon` / `restorecon` | `[ROOT]` (`uid=0`) | Preinstalled (`/system/bin`) | SELinux enforcement audit and file context repair |

## Shizuku and rish

Provides persistent on-device `uid=2000` execution without keeping a PC connected.

### Install

Install **Shizuku** (`moe.shizuku.privileged.api`) from GitHub Releases or Google Play, start via Wireless Debugging, and export `rish` + `rish_shizuku.dex` into Termux `$PREFIX/bin/`.

### Real-World Usage

`[NON-ROOT]` (Termux shell invoking `rish`)

```bash
# Disable Android 12+ Phantom Process Killer directly from the phone (no PC needed)
rish -c '/system/bin/device_config set_sync_disabled_for_tests persistent'
rish -c '/system/bin/device_config put activity_manager max_phantom_processes 2147483647'

# Exempt Termux from Doze without a host workstation
rish -c 'dumpsys deviceidle whitelist +com.termux'

# Query privileged system diagnostics normally blocked from Termux UID
rish -c 'dumpsys thermalservice | grep -E "Current status|mValue" | head -n 15'

# Grant WRITE_SECURE_SETTINGS to an automation app
rish -c 'pm grant com.example.tool android.permission.WRITE_SECURE_SETTINGS'
```

> **Watch out:** Commands run through `rish` execute inside Android's `/system/bin/sh` environment with `uid=2000`, not Termux's `$PATH`. Termux binaries (`jq`, `rg`, `curl`) are not in `rish`'s default path—pipe `rish -c '...'` stdout back into Termux tools on the left/right side of the pipe.

## Canta, Hail, and App Ops

Non-root administrative apps powered by Shizuku `uid=2000` APIs.

### Install

- **Canta** (safe user-0 debloater backed by Universal Android Debloater lists): F-Droid / IzzyOnDroid (`org.samo_lego.canta`).
- **Hail** (lightweight package freezer using Shizuku `pm disable-user` or `pm suspend`): F-Droid (`com.aistra.hail`).
- **App Ops** (fine-grained runtime/background op manager beyond Android Settings): Google Play / GitHub (`rikka.appops`).

### Real-World Usage (CLI Equivalents via `rish`)

`[NON-ROOT]`

```bash
# Freeze/unfreeze a noisy app cleanly (equivalent to Hail freeze)
rish -c 'pm disable-user --user 0 com.example.noisyapp'
rish -c 'pm enable com.example.noisyapp'

# Restrict background run and wake-lock permissions via appops CLI
rish -c 'cmd appops set com.example.noisyapp RUN_IN_BACKGROUND deny'
rish -c 'cmd appops set com.example.noisyapp WAKE_LOCK ignore'

# Inspect all active appops overrides for a package
rish -c 'cmd appops get com.example.noisyapp'
```

> **Watch out:** In Canta, only remove packages tagged **Recommended** unless you have verified dependencies. Packages tagged **Advanced** or **Expert** frequently break VoLTE/IMS calling, WearOS pairing, or OEM lockscreen biometric dialogs. Canta preserves a one-tap **Restore** tab (`cmd package install-existing`) as long as the device still boots.

## Magisk and ksud CLI

Command-line administration interfaces for Magisk and KernelSU environments.

### Install

Installed automatically when patching `init_boot`/`boot` with Magisk or KernelSU.

### Real-World Usage

`[ROOT]`

```bash
# Magisk: check version, inspect DenyList targets, and add a package to DenyList
magisk -v
magisk --denylist status
magisk --denylist ls
magisk --denylist add com.bank.app

# Magisk: emergency module wipe (usable from early-boot ADB during a bootloop)
magisk --remove-modules

# KernelSU: list installed modules and inspect kernel/LKM status
ksud module list
ksud debug get-sign /data/app/.../base.apk
```

> **Watch out:** Enabling Magisk's built-in **Enforce DenyList** disables Zygisk modules for listed apps and hides basic mounts, while third-party **Shamiko** (used with ZygiskNext or Magisk Zygisk) requires **Enforce DenyList** to be turned *off* while keeping target apps *on* the DenyList. Misconfiguring that toggle is the primary cause of failed root hiding.

## ACC (Advanced Charging Controller)

Kernel-level charging daemon that protects lithium-ion cells on permanently plugged-in devices.

### Install

Flash `acc_*.zip` from `github.com/VR-25/acc/releases` inside Magisk, KernelSU, or APatch Manager and reboot (`[REBOOT]`).

### Real-World Usage

`[ROOT]`

```bash
# Print full battery telemetry, active switch, voltage (mV), current (mA), and daemon status
acc -i

# Probe all kernel charging switches and identify switches supporting battery idle (bypass) mode
acc -t

# Set server-grade 50–60% charge window with 40C thermal cutoff and idle mode priority
acc -s pc=60 rc=50 ct=40 rt=35 prioritize_batt_idle_mode=true

# Force charging to stop immediately for maintenance or temporarily charge to 80% once
acc -d
acc -f 80
```

> **Watch out:** Not all Android kernels expose a true power-path bypass (`batt_idle`) switch. On devices without hardware bypass support, ACC pauses charging by toggling input suspend—meaning the phone cycles gently between `rc` (50%) and `pc` (60%). Do *not* set `pc` and `rc` only 1–2% apart (e.g., `pc=60 rc=59`) on non-bypass hardware, or you will trigger hundreds of micro-charge cycles per day and wear the battery faster.

## AFWall+ and Root iptables/nftables

Per-application Linux netfilter egress filtering using Android's deterministic per-app UID allocation.

### Install

- **AFWall+**: Install from F-Droid (`dev.ukanth.ufirewall`).
- **`iptables` / `ip6tables` / `nft`**: Preinstalled in Android (`/system/bin/iptables`, `/system/bin/ip6tables`, or `/system/bin/nft` on newer kernels).

### Real-World Usage

`[ROOT]`

```bash
# Find the exact Linux UID assigned to any installed Android package
dumpsys package com.example.tracker | grep -m1 'userId='
# Example: userId=10248

# Inspect active IPv4/IPv6 OUTPUT filter chains (modern -S rule syntax)
iptables -S OUTPUT
ip6tables -S OUTPUT

# Block all outbound IPv4 and IPv6 traffic for a specific app UID immediately
iptables -I OUTPUT 1 -m owner --uid-owner 10248 -j REJECT
ip6tables -I OUTPUT 1 -m owner --uid-owner 10248 -j REJECT

# Inspect nftables ruleset on Android 12+ kernels with nf_tables enabled
nft list ruleset 2>/dev/null | head -n 60
```

> **Watch out:** Android creates both IPv4 and IPv6 connections (especially on cellular networks where IPv6 is primary). Blocking an app with `iptables` alone while ignoring `ip6tables` allows the app to bypass the firewall silently over IPv6. Always enable **IPv6 support** in AFWall+ Preferences -> Binaries -> IPv6 support, or apply dual-stack rules.

## SELinux Inspection Utilities

Standard Android kernel tools for inspecting mandatory access control state and repairing file contexts.

### Install

Preinstalled at `/system/bin/{getenforce,setenforce,chcon,restorecon}`.

### Real-World Usage

`[ROOT]`

```bash
# Verify SELinux mode (must report Enforcing in production)
getenforce

# Inspect SELinux security contexts on custom root scripts or binaries
ls -Z /data/adb/service.d/

# Restore default SELinux label defined by Android file_contexts
restorecon -R /data/adb/modules/

# Inspect recent SELinux AVC denials without disabling enforcing mode
dmesg | grep -i 'avc: denied' | tail -n 30
```

> **Watch out:** Running `setenforce 0` disables mandatory access controls globally across every Android sandbox and app process, immediately weakening kernel isolation and tripping integrity checks. Never put `setenforce 0` inside `/data/adb/service.d/` boot scripts; fix the specific file context with `chcon`/`restorecon` or use targeted `magiskpolicy` rules instead.
