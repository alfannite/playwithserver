# Elevated Android Ops Tips & Tricks

Tuning ACC bypass charging for 24/7 phone servers, surviving OTA updates with A/B root retention, running `device_config` PC-free via `rish`, and writing clean AFWall+ custom rules.

[← Back to Android](../README.md) | [Home](../../README.md)

## Contents

- [Verify True Battery Idle Bypass Mode in ACC](#verify-true-battery-idle-bypass-mode-in-acc)
- [Preserve Root Across Seamless A/B OTA Updates](#preserve-root-across-seamless-ab-ota-updates)
- [Automate On-Device Admin Tasks with rish](#automate-on-device-admin-tasks-with-rish)
- [AFWall+ Custom Script for Pocket Linux Servers](#afwall-custom-script-for-pocket-linux-servers)
- [Use Boot-Stage Scripts Safely in /data/adb](#use-boot-stage-scripts-safely-in-dataadb)

## Verify True Battery Idle Bypass Mode in ACC

When ACC reports idle/bypass support, verify that battery current actually drops near `0 mA` while the phone remains powered exclusively from USB/AC:

`[ROOT]`

```bash
# 1. Run switch probe while plugged into your actual production charger (5V/2A or PD brick)
acc -t

# 2. Pin the best switch that printed "battIdleMode=true" (example path varies by SoC/PMIC)
acc -s s="battery/input_suspend 0 0"

# 3. Apply conservative voltage + percentage ceiling for long-term 24/7 operation
#    max_charging_voltage=3920mV keeps Li-ion cells around ~55-60% stress-free plateau
acc -s pc=60 rc=50 mv=3920 ct=40 rt=35 prioritize_batt_idle_mode=true

# 4. Wait 60 seconds after hitting 60% and verify current is ~0 mA and status is Idle/Not charging
acc -i | grep -iE 'STATUS|CAPACITY|CURRENT_NOW|VOLTAGE_NOW|TEMP|POWER_NOW'
```

If `CURRENT_NOW` stays near `0` (typically `-15 mA` to `+15 mA`) while the CPU runs a load test (`yes > /dev/null &`), the PMIC is powering the motherboard directly from USB and bypassing the lithium cell completely.

## Preserve Root Across Seamless A/B OTA Updates

On A/B devices rooted with Magisk or KernelSU LKM, you can take official Android security updates without a PC if you patch the inactive slot *before* rebooting:

1. Download and let Android install the OTA update in the background.
2. **Do not tap Restart now** when the OTA finishes.
3. Open **Magisk Manager -> Install -> Install to Inactive Slot (After OTA)** (or in **KernelSU Manager -> Install -> Install to Inactive Slot**).
4. Wait for patching to finish, then tap **Reboot** from inside Magisk/KernelSU Manager.

> **Watch out:** Never use **Install to Inactive Slot** if you modified `/system`, `/vendor`, or `/product` directly, or if you flashed a custom kernel that does not match the incoming OTA's GKI ABI. Official OTAs verify block-level hashes of system partitions and abort if `/system` was touched; systemless modules in `/data/adb/modules` are safe.

## Automate On-Device Admin Tasks with rish

Combine Termux and `rish` to inspect and modify privileged Android settings on the go without carrying a laptop:

`[NON-ROOT]` (Termux shell with `rish` configured)

```bash
# Create a reusable wrapper to inspect why any background service was killed
cat > ~/bin/why-killed <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
PKG="${1:-com.termux}"
rish -c "dumpsys activity exit-info | grep -A 10 '$PKG' | head -n 35"
EOF
chmod 700 ~/bin/why-killed

# Re-apply Phantom Process Killer bypass + Doze whitelist in one on-device command
rish -c '
  /system/bin/device_config set_sync_disabled_for_tests persistent
  /system/bin/device_config put activity_manager max_phantom_processes 2147483647
  settings put global settings_enable_monitor_phantom_procs false
  dumpsys deviceidle whitelist +com.termux
  dumpsys deviceidle whitelist +com.termux.boot
'
```

## AFWall+ Custom Script for Pocket Linux Servers

When using AFWall+ in **Whitelist mode** (block everything except explicitly checked apps), inbound LAN SSH to Termux or WireGuard/Tailscale traffic can be dropped if input/loopback rules are too tight. Add a clean custom script in **AFWall+ -> Set custom script**:

`[ROOT]` (AFWall+ Custom Script)

```sh
IPTABLES=/system/bin/iptables
IP6TABLES=/system/bin/ip6tables

# Allow established/related inbound return traffic
$IPTABLES -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
$IP6TABLES -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow inbound SSH on port 8022 strictly from RFC1918 LAN management subnet
$IPTABLES -I INPUT 2 -s 192.168.1.0/24 -p tcp --dport 8022 -j ACCEPT

# Allow Android Private DNS (DNS-over-TLS TCP 853) from system netd UID (0)
$IPTABLES -I afwall-wifi 1 -p tcp --dport 853 -j ACCEPT
$IP6TABLES -I afwall-wifi 1 -p tcp --dport 853 -j ACCEPT
```

Always check these required system entries in AFWall+ Whitelist mode so networking does not break:
- `[0] (root) - Applications running as root` (required for `netd` DNS resolution)
- `(kernel) - Linux kernel` (required for WireGuard kernel module if used)
- `Termux` (and `Tailscale` / `WireGuard` if installed)

## Use Boot-Stage Scripts Safely in /data/adb

Magisk, KernelSU, and APatch all execute scripts in two standardized boot directories:

| Directory | Execution Timing | Safe Use Cases | Risk Level |
| --- | --- | --- | --- |
| `/data/adb/post-fs-data.d/` | Synchronous, blocks Android boot until finished (max ~40s) | Early bind mounts, `resetprop` tweaks before Zygote starts | High — a hanging script stalls boot |
| `/data/adb/service.d/` | Asynchronous, runs after `late_start` in background | `sysctl` tuning, starting custom daemons, firewall scripts | Low — safe for almost all admin tasks |

Always place operational scripts in `/data/adb/service.d/` and make them executable (`chmod 700`):

`[ROOT]`

```bash
cat > /data/adb/service.d/99-server-tuning.sh <<'EOF'
#!/system/bin/sh
# Wait until boot finishes before applying runtime tweaks
until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done

# Example: disable Wi-Fi power-save throttling for consistent SSH latency
iw dev wlan0 set power_save off 2>/dev/null || true
EOF
chmod 700 /data/adb/service.d/99-server-tuning.sh
```

> **Watch out:** Never write infinite loops without `sleep` or blocking commands into `/data/adb/post-fs-data.d/`. A script that never exits in `post-fs-data.d` freezes Android permanently on the boot animation until you trigger safe mode or remove the script from recovery.
