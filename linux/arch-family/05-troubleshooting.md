# Arch Family Troubleshooting

Symptom-to-fix matrix and recovery playbooks for `pacman` keyring failures, broken upgrades, `arch-chroot` boot repair, package downgrades, and network/systemd faults on Arch Linux, EndeavourOS, and CachyOS.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Fix PGP Signature and Keyring Errors](#fix-pgp-signature-and-keyring-errors)
- [Live USB Recovery with `arch-chroot`](#live-usb-recovery-with-arch-chroot)
- [Downgrading Broken Packages](#downgrading-broken-packages)
- [Fixing Pacman Locks, File Conflicts, and Partial Upgrades](#fixing-pacman-locks-file-conflicts-and-partial-upgrades)
- [Systemd, Network, and Journald Forensics](#systemd-network-and-journald-forensics)
- [High-Signal Diagnostic One-Liners](#high-signal-diagnostic-one-liners)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause / Fix |
| :--- | :--- | :--- |
| `signature from "..." is unknown trust` / `invalid or corrupted package (PGP signature)` | `pacman -Q archlinux-keyring; timedatectl status` | Stale keyring or skewed clock. Fix NTP, then run `sudo pacman -Sy archlinux-keyring && sudo pacman -Syu`. |
| `unable to lock database` (`/var/lib/pacman/db.lck`) | `pgrep -a pacman` | Interrupted transaction. Confirm no `pacman` is running, then `sudo rm /var/lib/pacman/db.lck`. |
| `exists in filesystem` during upgrade | `pacman -Qo /path/to/file` | Untracked file conflicts with package (often global `pip`/`npm` install). Move/remove conflicting file or use `--overwrite`. |
| Kernel panic / `ERROR: device 'UUID=...' not found` on boot | Boot `linux-lts` or live ISO; check `lsblk -f` and `/etc/mkinitcpio.conf` | Missing storage/fs module or truncated initramfs (e.g., `/boot` full during upgrade). `arch-chroot` and run `mkinitcpio -P`. |
| `error while loading shared libraries: libXYZ.so.N` | `ldd $(which binary) \| grep 'not found'` | Partial upgrade (`pacman -Sy pkg`). Run full `sudo pacman -Syu` (or from live USB via `pacman --sysroot /mnt -Syu`). |
| Docker / WireGuard / USB fails right after `pacman -Syu` | `uname -r; ls /usr/lib/modules/` | Running kernel's module directory deleted on upgrade. Reboot or install `kernel-modules-hook`. |
| `Could not resolve host` after upgrade | `resolvectl status; ls -l /etc/resolv.conf` | Broken `/etc/resolv.conf` symlink or stopped `systemd-resolved` / `NetworkManager`. |
| Account locked after typos (`Account locked due to 3 failed logins`) | `sudo faillock --user <user>` | PAM `faillock` triggered. Clear via `sudo faillock --user <user> --reset`. |

## Fix PGP Signature and Keyring Errors

Always verify system time first; expired clock skew makes every valid PGP signature look invalid.

```bash
# [ROOT] 1. Verify clock accuracy
timedatectl status
sudo timedatectl set-ntp true

# [ROOT] 2. Refresh archlinux-keyring (and cachyos-keyring / endeavouros-keyring if applicable)
sudo pacman -Sy --needed archlinux-keyring
sudo pacman -Syu
```

If the local GPG keyring database in `/etc/pacman.d/gnupg/` is corrupted, rebuild it cleanly:

```bash
# [ROOT] [DESTRUCTIVE] Reset and repopulate pacman GPG keyring
sudo rm -rf /etc/pacman.d/gnupg
sudo pacman-key --init
sudo pacman-key --populate archlinux
# On EndeavourOS also run: sudo pacman-key --populate endeavouros
# On CachyOS also run:     sudo pacman-key --populate cachyos
sudo pacman -Syu
```

> **Watch out:** Never permanently set `SigLevel = Never` in `/etc/pacman.conf` to bypass keyring errors. Disabling signature verification allows MITM package tampering on every future upgrade.

## Live USB Recovery with `arch-chroot`

When a bad kernel upgrade, full `/boot`, or broken initramfs prevents booting (and `linux-lts` is unavailable), boot the Arch/EndeavourOS/CachyOS live ISO.

### Mount Partitions and Chroot `[ROOT]`

```bash
# [ROOT] Identify root, EFI, and boot partitions
lsblk -f

# Mount root (for ext4/xfs)
mount /dev/nvme0n1p2 /mnt

# For Btrfs root with @ subvolume (EndeavourOS/CachyOS default):
# mount -o subvol=@ /dev/nvme0n1p2 /mnt
# mount -o subvol=@home /dev/nvme0n1p2 /mnt/home

# Mount EFI / boot partition (check /mnt/etc/fstab to confirm whether it mounts at /boot or /efi)
mount /dev/nvme0n1p1 /mnt/boot

# Enter the installed system
arch-chroot /mnt
```

### Repair Kernel, Initramfs, and Bootloader Inside Chroot `[ROOT]` `[REBOOT]`

```bash
# [ROOT] Inside arch-chroot: check if /boot filled up
df -h /boot

# Reinstall kernel and rebuild all initramfs images
pacman -Syu linux linux-lts
mkinitcpio -P

# Reinstall GRUB (UEFI) if bootloader was wiped by firmware/Windows update
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Or update systemd-boot
bootctl install
bootctl update

# Exit cleanly and reboot
exit
umount -R /mnt
reboot
```

### Recovering a Broken `pacman` Binary from Live ISO `[ROOT]`

If a partial upgrade broke `glibc`, `openssl`, or `pacman` so `arch-chroot` fails with `error while loading shared libraries`, use the live ISO's `pacman` against the mounted root:

```bash
# [ROOT] From live ISO outside chroot
pacman --sysroot /mnt -Syu
```

## Downgrading Broken Packages

### Roll Back from Local Cache `[ROOT]`

```bash
# [NON-ROOT] List cached versions of a package
ls -la /var/cache/pacman/pkg/linux-6.*

# [ROOT] Install a specific cached package archive
sudo pacman -U /var/cache/pacman/pkg/linux-6.11.6.arch1-1-x86_64.pkg.tar.zst
```

### Roll Back from the Arch Linux Archive (ALA) `[ROOT]`

If the cache was pruned, pull a package directly by URL or use `downgrade`:

```bash
# [ROOT] Install a specific historical version from Arch Linux Archive
sudo pacman -U https://archive.archlinux.org/packages/m/mesa/mesa-1%3A24.2.5-1-x86_64.pkg.tar.zst
```

Temporarily pin a broken package in `/etc/pacman.conf` until upstream fixes it:

```ini
# /etc/pacman.conf under [options]
IgnorePkg = mesa linux-nvidia
```

> **Watch out:** Leaving packages in `IgnorePkg` indefinitely causes library ABI mismatches during subsequent upgrades. Remove `IgnorePkg` as soon as the upstream fix lands and run `sudo pacman -Syu`.

## Fixing Pacman Locks, File Conflicts, and Partial Upgrades

### Stale Database Lock `[ROOT]`

```bash
# [ROOT] Confirm no pacman process is alive before deleting the lock
pgrep -af pacman || sudo rm -f /var/lib/pacman/db.lck
```

### File Conflict (`exists in filesystem`) `[ROOT]`

```bash
# [NON-ROOT] Check whether any package owns the conflicting file
pacman -Qo /usr/lib/python3.12/site-packages/foo.py

# [ROOT] If unowned (e.g., installed via sudo pip), remove or overwrite selectively
sudo pacman -Syu --overwrite '/usr/lib/python3.12/site-packages/foo/*'
```

## Systemd, Network, and Journald Forensics

```bash
# [NON-ROOT] List all failed systemd units
systemctl --failed

# [NON-ROOT] Inspect full unit status and recent logs for a failing service
systemctl status nginx.service --no-pager -l
journalctl -u nginx.service -b -n 100 --no-pager

# [NON-ROOT] Diagnose DNS and NetworkManager / systemd-networkd state
resolvectl status
networkctl list
nmcli general status
nmcli device show

# [ROOT] Flush DNS cache when systemd-resolved serves stale records
sudo resolvectl flush-caches
```

## High-Signal Diagnostic One-Liners

```bash
# [NON-ROOT] Check recently upgraded packages from pacman.log (last 40 changes)
grep -E '\[(ALPM)\] (upgraded|installed|removed)' /var/log/pacman.log | tail -n 40

# [ROOT] Find processes still holding deleted shared libraries after an upgrade (services needing restart)
sudo lsof +c 0 | awk '/DEL.*\/usr\/lib\// {print $1, $2}' | sort -u

# [NON-ROOT] Check kernel ring buffer for hardware/OOM/filesystem errors
dmesg -T --level=err,crit,alert,emerg

# [ROOT] Find the top 15 largest directories under /var
sudo du -xh --max-depth=2 /var 2>/dev/null | sort -hr | head -n 15

# [NON-ROOT] Check for broken symlinks in /etc/systemd/system
find /etc/systemd/system -xtype l -ls
```
