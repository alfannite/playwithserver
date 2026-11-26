# Arch Family Tips and Tricks

High-leverage `pacman` hooks, `.pacnew` workflows, `mkinitcpio` optimizations, package query one-liners, and kernel tuning for Arch Linux, EndeavourOS, and CachyOS.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Custom Pacman Hooks](#custom-pacman-hooks)
- [Managing `.pacnew` and `.pacsave` Files](#managing-pacnew-and-pacsave-files)
- [High-Signal Pacman Queries and Package Lists](#high-signal-pacman-queries-and-package-lists)
- [Initramfs Optimization and Unified Kernel Images](#initramfs-optimization-and-unified-kernel-images)
- [Surviving Kernel Upgrades Without Rebooting](#surviving-kernel-upgrades-without-rebooting)
- [ZRAM Swap and Kernel Tuning](#zram-swap-and-kernel-tuning)
- [EndeavourOS and CachyOS Specifics](#endeavouros-and-cachyos-specifics)

## Custom Pacman Hooks

Drop-in `alpm-hooks` in `/etc/pacman.d/hooks/` run automatically before or after `pacman` transactions.

### Auto-Prune Cache on Every Upgrade `[ROOT]`

```ini
# /etc/pacman.d/hooks/90-paccache.hook
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Pruning pacman cache (keeping 2 versions)...
When = PostTransaction
Exec = /usr/bin/paccache -rk2
```

### Alert on `.pacnew` Files After Upgrade `[ROOT]`

```ini
# /etc/pacman.d/hooks/95-pacnew-alert.hook
[Trigger]
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Checking for .pacnew files...
When = PostTransaction
Exec = /usr/bin/sh -c 'pacdiff -o | sed "s/^/  PACNEW: /"'
```

### Auto-Clean Orphaned Packages Audit `[ROOT]`

```ini
# /etc/pacman.d/hooks/96-orphans.hook
[Trigger]
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Listing orphaned packages...
When = PostTransaction
Exec = /usr/bin/sh -c 'pacman -Qtdq || true'
```

> **Watch out:** Keep `PreTransaction` hooks fast and non-interactive. If a `PreTransaction` hook with `AbortOnFail` exits non-zero, `pacman` cancels the entire upgrade.

## Managing `.pacnew` and `.pacsave` Files

When an upgraded package ships a modified default config for a file you edited, `pacman` preserves your file and writes `<file>.pacnew`.

```bash
# [NON-ROOT] List all pending .pacnew/.pacsave files without modifying anything
pacdiff -o

# [ROOT] Interactively inspect and merge using vimdiff (or meld/nvim -d)
sudo DIFFPROG="nvim -d" pacdiff

# [NON-ROOT] Quick diff of a specific config file
diff -u /etc/mkinitcpio.conf /etc/mkinitcpio.conf.pacnew
```

| Action in `pacdiff` | Behavior | When to Use |
| :--- | :--- | :--- |
| `(V)iew` | Opens `DIFFPROG` side-by-side | Always inspect first; merge new syntax into existing file |
| `(R)emove` | Deletes `.pacnew` | After merging required changes or when keeping local config |
| `(O)verwrite` | Replaces live config with `.pacnew` | Only for uncustomized configs (never `passwd`/`shadow`/`fstab`) |
| `(S)kip` | Leaves both files untouched | Defer until maintenance window |

## High-Signal Pacman Queries and Package Lists

```bash
# [NON-ROOT] Export reproducible package manifests for rebuilds
pacman -Qqen > native-packages.txt
pacman -Qqem > aur-packages.txt

# [ROOT] Restore native packages on a fresh host
sudo pacman -S --needed - < native-packages.txt

# [NON-ROOT] List explicitly installed packages sorted by installed size (largest first)
pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4$5, name}' | sort -hr | head -n 25

# [NON-ROOT] Find unused orphan dependencies and inspect before removing
pacman -Qdtq
# [ROOT] Remove orphans recursively
sudo pacman -Rns $(pacman -Qdtq)

# [NON-ROOT] Check which installed packages are from AUR / foreign repos
pacman -Qm

# [NON-ROOT] List all files owned by a package (useful for finding systemd units & configs)
pacman -Ql nginx | grep -E '/etc/|/usr/lib/systemd/'

# [NON-ROOT] Check Arch news feed before running a major upgrade
curl -s https://archlinux.org/feeds/news/ | grep -oP '(?<=<title>).*?(?=</title>)' | sed -n '2,6p'
```

## Initramfs Optimization and Unified Kernel Images

### Faster Boot and Smaller Initramfs with `zstd` and `systemd` Hooks `[ROOT]`

In `/etc/mkinitcpio.conf`, switch from legacy busybox `udev` hooks to `systemd` hooks for faster parallel device probing and native `systemd-cryptsetup` support.

```bash
# /etc/mkinitcpio.conf snippet (non-encrypted standard server)
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-3 -T0)
```

```bash
# [ROOT] Rebuild initramfs and measure image size
sudo mkinitcpio -P
ls -lh /boot/initramfs-*.img
```

### Unified Kernel Images (UKI) for `systemd-boot` `[ROOT]`

A UKI bundles kernel, microcode, initramfs, and kernel cmdline into a single `.efi` binary stored in `/efi/EFI/Linux/`, simplifying Secure Boot signing.

```bash
# [ROOT] Define kernel command line once
echo 'root=UUID=YOUR-ROOT-UUID rw quiet' | sudo tee /etc/kernel/cmdline

# [ROOT] Edit /etc/mkinitcpio.d/linux.preset to enable default_uki
# default_uki="/efi/EFI/Linux/arch-linux.efi"
# fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
sudo mkinitcpio -P
```

> **Watch out:** When switching from `udev` to `systemd` hooks on a LUKS-encrypted root, replace `encrypt` with `sd-encrypt` and convert `cryptdevice=UUID=...:root` kernel parameters to `rd.luks.name=UUID=root`. Failing to match hook syntax leaves you at an emergency shell.

## Surviving Kernel Upgrades Without Rebooting

On Arch, upgrading `linux` deletes `/usr/lib/modules/<old-running-kernel>/` immediately. Until you reboot, loading any new kernel module (USB storage, WireGuard, Docker overlay/iptables, NFS) fails because the running kernel's module directory is gone.

```bash
# [ROOT] Install kernel-modules-hook to preserve running kernel modules until reboot
sudo pacman -S --needed kernel-modules-hook
sudo systemctl enable --now linux-modules-cleanup.service
```

Verify whether a reboot is needed because the running kernel differs from the installed kernel:

```bash
# [NON-ROOT] Compare running kernel version vs installed package
echo "Running:   $(uname -r)"
echo "Installed: $(pacman -Q linux linux-lts linux-cachyos 2>/dev/null)"
```

## ZRAM Swap and Kernel Tuning

### Configure Compressed RAM Swap with `zram-generator` `[ROOT]`

```bash
# [ROOT] Install systemd zram-generator
sudo pacman -S --needed zram-generator

sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF

sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
zramctl
```

### Practical Server `sysctl` Defaults `[ROOT]`

```bash
# [ROOT] Optimize swap behavior for ZRAM, inotify watches, and TCP BBR congestion control
sudo tee /etc/sysctl.d/90-performance.conf >/dev/null <<'EOF'
vm.swappiness = 100
vm.page-cluster = 0
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sudo sysctl --system
```

## EndeavourOS and CachyOS Specifics

### CachyOS x86-64-v3 / v4 Optimized Repos

Check whether your CPU supports `x86-64-v3` (AVX2) or `x86-64-v4` (AVX-512) before enabling optimized repos:

```bash
# [NON-ROOT] Query ld.so for highest supported x86-64 microarchitecture level
/lib/ld-linux-x86-64.so.2 --help | grep supported
```

### EndeavourOS Quick Utilities

```bash
# [ROOT] Rank EndeavourOS-specific mirrors alongside Arch mirrors
sudo eos-rankmirrors

# [NON-ROOT] Check Arch + EndeavourOS combined update count safely without modifying sync DB
checkupdates
```

> **Watch out:** Never run `pacman -Sy` just to check for pending updates. Use `checkupdates` (from `pacman-contrib`), which downloads sync databases into an isolated temporary directory without touching `/var/lib/pacman/sync/`.
