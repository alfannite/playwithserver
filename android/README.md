# Android Administration & Edge-Server Hub

Operational field manual for administering Android devices via ADB/Fastboot, turning spare phones into 24/7 Termux Linux servers, managing Root/Shizuku privileges, and running mobile networking/VPN tools.

[← Home](../README.md)

## Variant Guides

| Variant | Target Scope | 01 Bootstrap | 02 Tools | 03 Tips & Tricks | 04 Hardening | 05 Troubleshooting |
| --- | --- | --- | --- | --- | --- | --- |
| `adb-fastboot` | Wireless ADB, `scrcpy`, `dumpsys`, `logcat`, safe user-0 debloat, A/B slot flashing | [Bootstrap](adb-fastboot/01-bootstrap.md) | [Tools](adb-fastboot/02-tools.md) | [Tips & Tricks](adb-fastboot/03-tips-tricks.md) | [Hardening](adb-fastboot/04-hardening.md) | [Troubleshooting](adb-fastboot/05-troubleshooting.md) |
| `termux-linux` | F-Droid Termux, OpenSSH, `proot-distro`, `termux-services`, wake-lock, `cloudflared` | [Bootstrap](termux-linux/01-bootstrap.md) | [Tools](termux-linux/02-tools.md) | [Tips & Tricks](termux-linux/03-tips-tricks.md) | [Hardening](termux-linux/04-hardening.md) | [Troubleshooting](termux-linux/05-troubleshooting.md) |
| `root-shizuku-ops` | Shizuku non-root ops, Magisk/KernelSU, ACC 50-60% battery cap, `iptables`/firewall | [Bootstrap](root-shizuku-ops/01-bootstrap.md) | [Tools](root-shizuku-ops/02-tools.md) | [Tips & Tricks](root-shizuku-ops/03-tips-tricks.md) | [Hardening](root-shizuku-ops/04-hardening.md) | [Troubleshooting](root-shizuku-ops/05-troubleshooting.md) |
| `mobile-networking` | PCAPdroid capture, WireGuard/Tailscale exit node, `gnirehtet`, Private DNS (DoT) | [Bootstrap](mobile-networking/01-bootstrap.md) | [Tools](mobile-networking/02-tools.md) | [Tips & Tricks](mobile-networking/03-tips-tricks.md) | [Hardening](mobile-networking/04-hardening.md) | [Troubleshooting](mobile-networking/05-troubleshooting.md) |

## Capability Matrix: Non-Root ADB vs Shizuku vs Termux vs Root

| Capability | Non-Root ADB (USB / Wireless) | Shizuku (`uid=2000` on-device) | Termux (F-Droid, unprivileged) | Root (Magisk / KernelSU, `uid=0`) |
| --- | --- | --- | --- | --- |
| Requires unlocked bootloader | No | No | No | Yes |
| Breaks banking / Play Integrity | No | No | No | Often (requires mitigation) |
| Disable/uninstall bloatware for user 0 | Yes (`pm uninstall --user 0`) | Yes (via Canta / Hail / `rish`) | No | Yes (systemless debloat) |
| Disable Android 12+ Phantom Process Killer | Yes (`device_config put`) | Yes (via `rish`) | No (must be set via ADB/Shizuku) | Yes |
| Run SSH server & cron/services | No (ADB shell only) | No | Yes (`sshd` on port >1024, `sv`) | Yes (ports <1024, native chroot) |
| Bind privileged ports (`< 1024`) | No | No | No (use `8022`, `8080`, or `cloudflared`) | Yes |
| Hardware battery charge limit (50-60%) | No (unless OEM exposes setting) | No | No | Yes (ACC — Advanced Charging Controller) |
| Full `iptables`/`nftables` firewall | No (use VPN-based firewall) | No | No | Yes (AFWall+, raw `iptables`/`nft`) |
| Packet capture (PCAP) | Partial (`tcpdump` unavailable) | No | No | Yes (native `tcpdump` / PCAPdroid root) |
| True Docker / native kernel namespaces | No | No | No (`proot-distro` uses ptrace, or QEMU) | Only with custom kernel built with cgroups/namespaces |

> **Watch out:** Never install Termux from the Google Play Store. The Play Store build is deprecated and incompatible with current Termux package repositories. Always install Termux and `Termux:Boot` from F-Droid or the official GitHub Releases page.

## Related Scripts

- [scripts/android/termux-pocket-server.sh](../scripts/android/termux-pocket-server.sh) — Bootstrap Termux with OpenSSH, `tmux`, `termux-services`, wake-lock, and core ops CLI tools
- [scripts/android/adb-device-audit.sh](../scripts/android/adb-device-audit.sh) — Pull battery health, thermal state, storage, network interfaces, and running services over ADB
