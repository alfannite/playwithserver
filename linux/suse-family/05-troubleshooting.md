# openSUSE Family Troubleshooting

Symptom-to-fix matrix and recovery playbooks for `zypper` solver faults, Btrfs `ENOSPC` snapshot exhaustion, GRUB read-only snapshot rollbacks, MicroOS `transactional-update` failures, SELinux/AppArmor denials, and networking conflicts.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Booting a Read-Only Snapshot and Running `snapper rollback`](#booting-a-read-only-snapshot-and-running-snapper-rollback)
- [Fixing Btrfs `No space left on device` from Snapshots](#fixing-btrfs-no-space-left-on-device-from-snapshots)
- [Recovering MicroOS `transactional-update` Failures](#recovering-microos-transactional-update-failures)
- [Diagnosing SELinux and AppArmor Denials](#diagnosing-selinux-and-apparmor-denials)
- [Fixing `zypper` Locks, Solver Conflicts, and Network Stack Clashes](#fixing-zypper-locks-solver-conflicts-and-network-stack-clashes)
- [High-Signal Diagnostic One-Liners](#high-signal-diagnostic-one-liners)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause / Fix |
| :--- | :--- | :--- |
| Broken boot or regression after `zypper dup` / `up` | Boot GRUB -> `Start bootloader from a read-only snapshot` | Select pre-upgrade snapshot, test system, then run `sudo snapper rollback` and reboot. |
| `No space left on device` even though `df -h` shows free space | `sudo btrfs filesystem usage /; sudo snapper list` | Btrfs metadata/snapshot exhaustion. Delete old snapshots with `snapper delete`, then run a filtered metadata balance. |
| MicroOS `transactional-update` fails or staged update breaks boot | `sudo transactional-update status; journalctl -u transactional-update` | Run `sudo transactional-update rollback` (or boot previous snapshot from GRUB) and inspect `/var/log/transactional-update.log`. |
| `Permission denied` on a valid `0644` file/port (Tumbleweed/MicroOS) | `sudo ausearch -m avc -ts recent; ls -Z /path` | SELinux denial. Fix context with `restorecon -Rv` or port type with `semanage port`. |
| `Permission denied` on Leap daemon with normal Unix perms | `sudo aa-status; dmesg \| grep -i apparmor` | AppArmor profile restriction. Inspect audit logs and refine profile with `sudo aa-logprof`. |
| `System management is locked by the application with pid ...` | `ps -fp <pid>` | Background `packagekitd` or `transactional-update` holds `/run/zypp.pid`. Wait for completion or stop `packagekit` on servers. |
| `sudo` rejects user's password on fresh openSUSE | `grep targetpw /etc/sudoers /usr/etc/sudoers` | openSUSE defaults to `Defaults targetpw` (asks for root password). Add `Defaults:%wheel !targetpw` in `/etc/sudoers.d/10-wheel`. |
| Duplicate IPs, flapping routes, or DNS overwritten | `systemctl is-active NetworkManager wicked` | Both `wicked` and `NetworkManager` enabled or leftover `/etc/sysconfig/network/ifcfg-*`. Disable one stack completely. |
| Services keep using vulnerable OpenSSL/glibc after patching | `sudo zypper ps -s` | Daemons still map deleted `.so` files. Restart listed systemd services. |

## Booting a Read-Only Snapshot and Running `snapper rollback`

When a Tumbleweed or Leap upgrade breaks a kernel, driver, or critical daemon:

1. Reboot and select **`Start bootloader from a read-only snapshot`** in the GRUB menu.
2. Choose the `pre` snapshot taken immediately before the failing `zypper` transaction (timestamps and descriptions are shown in GRUB).
3. Boot into the read-only snapshot and verify networking, storage, and services work normally.
4. Make the snapshot the new writable default root:

```bash
# [ROOT] [REBOOT] Inside the booted read-only snapshot
sudo snapper rollback
# Snapper creates a new read-write snapshot cloned from the currently booted snapshot and sets it as default

sudo reboot
```

After rebooting into the rolled-back writable root, confirm the active default subvolume:

```bash
# [ROOT] Verify current default snapshot (marked with '*')
sudo snapper list
```

> **Watch out:** Never try to run `zypper` or edit services permanently while booted in a read-only snapshot before running `snapper rollback` and rebooting. Wait until you are booted into the new read-write snapshot first.

## Fixing Btrfs `No space left on device` from Snapshots

```bash
# [ROOT] 1. Inspect true Btrfs space allocation and metadata usage
sudo btrfs filesystem usage -T /

# 2. List snapshots and identify oldest non-active snapshots
sudo snapper list

# 3. Delete a range of old snapshots (NEVER delete snapshot 0 or the active '*' snapshot)
sudo snapper delete --sync 10-35

# 4. If metadata is full and balance refuses to start, free space or run a targeted low-usage data balance
sudo btrfs balance start -dusage=10 /
sudo btrfs balance start -dusage=25 /

# 5. Confirm recovered unallocated space
sudo btrfs filesystem usage -T /
```

> **Watch out:** Running an unfiltered `btrfs balance start /` rewrites the entire filesystem, saturates disk I/O for hours, and can worsen `ENOSPC` on nearly full drives. Always filter with `-dusage=10` (or `-musage=10`) incrementally.

## Recovering MicroOS `transactional-update` Failures

```bash
# [ROOT] Inspect transactional-update log for exact zypper/RPM failure reason
sudo tail -n 100 /var/log/transactional-update.log

# Check active vs pending snapshots
sudo transactional-update status

# Discard unused/failed pending snapshots
sudo transactional-update cleanup-snapshots

# [ROOT] [REBOOT] Roll back to the last known-good snapshot
sudo transactional-update rollback
sudo reboot
```

If MicroOS fails to boot a new snapshot and `health-checker` did not auto-revert, boot the previous snapshot from GRUB and run `sudo transactional-update rollback && sudo reboot`.

## Diagnosing SELinux and AppArmor Denials

### SELinux (Tumbleweed & MicroOS) `[ROOT]`

```bash
# [ROOT] List recent AVC denials in human-readable form
sudo ausearch -m avc,user_avc -ts recent -i

# Inspect SELinux contexts on files and running processes
ls -Z /srv/app
ps -eZ | grep nginx

# Temporarily switch to permissive mode ONLY to verify whether SELinux is the root cause
sudo setenforce 0
# Test failing action, collect AVC logs, then immediately re-enable enforcing:
sudo setenforce 1

# Fix common mislabeled file/directory trees
sudo restorecon -Rv /srv/app
```

### AppArmor (openSUSE Leap) `[ROOT]`

```bash
# [ROOT] Check AppArmor denial events in kernel/audit log
sudo journalctl -k -g 'apparmor="DENIED"' -b

# Temporarily switch a single misbehaving profile to complain mode while diagnosing
sudo aa-complain /etc/apparmor.d/usr.sbin.nginx

# Update profile rules interactively and re-enforce
sudo aa-logprof
sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx
```

## Fixing `zypper` Locks, Solver Conflicts, and Network Stack Clashes

### PackageKit Locking `zypper` on Headless Servers `[ROOT]`

```bash
# [ROOT] Identify locking PID
cat /run/zypp.pid && ps -fp "$(cat /run/zypp.pid)"

# Mask packagekit on headless servers where zypper/transactional-update manages packages
sudo systemctl disable --now packagekit.service
sudo systemctl mask packagekit.service
```

### Resolve Stale Repository Metadata `[ROOT]`

```bash
# [ROOT] Clean cached repo metadata and force full refresh
sudo zypper clean --metadata
sudo zypper ref --force
```

### Switching Cleanly from `wicked` to `NetworkManager` `[ROOT]` `[REBOOT]`

```bash
# [ROOT] Ensure NetworkManager is installed before stopping wicked (avoid remote lockout)
sudo zypper in --no-recommends NetworkManager
sudo systemctl disable wicked.service wickedd.service
sudo systemctl enable NetworkManager.service
# Reboot or switch atomically via console/screen
sudo reboot
```

## High-Signal Diagnostic One-Liners

```bash
# [NON-ROOT] Check OS variant, Tumbleweed snapshot date (VERSION_ID), and running kernel
cat /etc/os-release && uname -r

# [ROOT] Inspect recently installed/upgraded packages from zypper history
sudo tail -n 40 /var/log/zypp/history | awk -F'|' '{print $1, $2, $3, $4}'

# [NON-ROOT] List all failed systemd units and boot errors
systemctl --failed
journalctl -b -p err..emerg --no-pager

# [ROOT] Verify which running processes need restart after package updates
sudo zypper ps -s

# [ROOT] Check Btrfs space and snapshot count in one pass
sudo btrfs filesystem usage -T / && sudo snapper list | wc -l
```
