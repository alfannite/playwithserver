# Arch Family Bootstrap Guide

First-boot provisioning, mirror ranking, `pacman` configuration, fallback kernel setup, and AUR helper installation for Arch Linux, EndeavourOS, and CachyOS servers and workstations.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Variant Differences](#variant-differences)
- [Configure Pacman and Mirrors](#configure-pacman-and-mirrors)
- [Keyring and Full System Sync](#keyring-and-full-system-sync)
- [Base Admin Packages and Time Sync](#base-admin-packages-and-time-sync)
- [Fallback Kernel, Microcode, and Initramfs](#fallback-kernel-microcode-and-initramfs)
- [Admin User, SSH, and Guest Agents](#admin-user-ssh-and-guest-agents)
- [AUR Helper Bootstrap](#aur-helper-bootstrap)
- [Automated Maintenance Timers](#automated-maintenance-timers)

## Variant Differences

| Feature | Arch Linux | EndeavourOS | CachyOS |
| :--- | :--- | :--- | :--- |
| Default repos | `core`, `extra` | `core`, `extra`, `endeavouros` | `cachyos-v3`/`v4`, `cachyos`, `core`, `extra` |
| Default kernel | `linux` | `linux` + `linux-headers` | `linux-cachyos` (BORE/LTO) |
| Mirror ranker | `reflector` | `reflector` / `eos-rankmirrors` | `cachyos-rate-mirrors` + `reflector` |
| Default AUR helper | None (manual build) | `yay` | `paru` |
| Bootloader default | Manual (`systemd-boot` or GRUB) | `systemd-boot` or GRUB | `systemd-boot` / `limine` / GRUB |

## Configure Pacman and Mirrors

### Tune `/etc/pacman.conf` `[ROOT]`

Enable colored output, parallel downloads, and verbose package version diffs before installing packages.

```bash
# [ROOT] Enable Color, ParallelDownloads, CheckSpace, and VerbosePkgLists
sudo sed -i \
  -e 's/^#Color/Color/' \
  -e 's/^#VerbosePkgLists/VerbosePkgLists/' \
  -e 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' \
  /etc/pacman.conf

# Verify active options
grep -E '^(Color|VerbosePkgLists|ParallelDownloads|CheckSpace)' /etc/pacman.conf
```

### Rank Mirrors with `reflector` `[ROOT]`

`reflector` queries the Arch Mirror Status JSON API and filters by sync recency, protocol, and throughput.

```bash
# [ROOT] Install reflector
sudo pacman -S --needed reflector

# Back up current mirrorlist and write top 15 HTTPS mirrors synced in the last 12 hours
sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
sudo reflector \
  --protocol https \
  --age 12 \
  --latest 20 \
  --fastest 15 \
  --sort rate \
  --save /etc/pacman.d/mirrorlist
```

On CachyOS, also refresh CachyOS-specific repositories:

```bash
# [ROOT] CachyOS only: rank CachyOS and Arch mirrors together
sudo cachyos-rate-mirrors
```

> **Watch out:** Restricting `--country` to a single small country with `--age 6` can return zero mirrors and overwrite `/etc/pacman.d/mirrorlist` with an empty file. Always include `--latest 20` or omit `--country` on cloud servers with good peering.

## Keyring and Full System Sync

Fresh images or boxes left offline for months often fail PGP signature verification because `archlinux-keyring` is stale. Update the keyring first, then run a full system upgrade.

```bash
# [ROOT] Refresh keyring before full sync on older images
sudo pacman -Sy --needed archlinux-keyring
sudo pacman -Syu
```

> **Watch out:** Never install normal packages with `pacman -Sy <pkg>` (partial upgrade). Arch is a rolling release without ABI pinning between shared libraries; installing a single package against a synced database without upgrading the rest of the system breaks core binaries like `openssl`, `glibc`, or `pacman` itself. Always use `pacman -Syu <pkg>`.

## Base Admin Packages and Time Sync

### Install Core Utilities `[ROOT]`

```bash
# [ROOT] Core admin, build toolchain, man pages, and pacman helpers
sudo pacman -Syu --needed \
  base-devel git vim neovim tmux curl wget \
  pacman-contrib man-db man-pages texinfo \
  openssh bash-completion htop btop \
  iproute2 bind dnsutils inetutils traceroute mtr tcpdump \
  lsof strace sysstat ncdu jq rsync
```

### Enable Time Synchronization `[ROOT]`

Accurate clocks prevent TLS failures, Kerberos/WireGuard handshake drops, and PGP key validity errors.

```bash
# [ROOT] Option A: Lightweight systemd-timesyncd (default on Arch)
sudo timedatectl set-ntp true
sudo timedatectl set-timezone UTC
timedatectl status

# [ROOT] Option B: chrony (preferred for VMs, hosts with clock drift, or NTP servers)
sudo pacman -S --needed chrony
sudo systemctl disable --now systemd-timesyncd
sudo systemctl enable --now chronyd
chronyc tracking
```

## Fallback Kernel, Microcode, and Initramfs

### Install `linux-lts` and CPU Microcode `[ROOT]` `[REBOOT]`

Keep `linux-lts` installed alongside `linux` (or `linux-cachyos`) so a kernel regression never leaves a remote server unbootable.

```bash
# [ROOT] Install LTS kernel and headers (required for DKMS modules like ZFS/WireGuard/NVIDIA)
sudo pacman -S --needed linux-lts linux-lts-headers

# Install CPU microcode matching host hardware (bare metal only; skip inside VMs)
# Intel CPUs:
sudo pacman -S --needed intel-ucode
# AMD CPUs:
sudo pacman -S --needed amd-ucode
```

### Verify `mkinitcpio` Presets and Regenerate Initramfs `[ROOT]`

Inspect `/etc/mkinitcpio.conf` and rebuild all kernel presets after changing hooks, modules, or microcode.

```bash
# [ROOT] Inspect active hooks and modules
grep -E '^(MODULES|BINARIES|FILES|HOOKS|COMPRESSION)=' /etc/mkinitcpio.conf

# Regenerate all initramfs images (/etc/mkinitcpio.d/*.preset)
sudo mkinitcpio -P
```

### Update Bootloader Entries `[ROOT]` `[REBOOT]`

```bash
# [ROOT] GRUB: regenerate grub.cfg so linux-lts and microcode are picked up
sudo grub-mkconfig -o /boot/grub/grub.cfg

# [ROOT] systemd-boot: verify entries exist in /boot/loader/entries/
ls -la /boot/loader/entries/
bootctl status
```

> **Watch out:** `systemd-boot` does not auto-create a loader entry when you install `linux-lts` on vanilla Arch unless you use `kernel-install` or a pacman hook. Copy your existing `/boot/loader/entries/arch.conf` to `arch-lts.conf`, update `linux /vmlinuz-linux-lts` and `initrd /initramfs-linux-lts.img`, and confirm with `bootctl list`.

## Admin User, SSH, and Guest Agents

### Create Non-Root Admin User `[ROOT]`

```bash
# [ROOT] Create admin user in wheel group
sudo useradd -m -G wheel -s /bin/bash ops
sudo passwd ops

# Enable wheel group in sudoers using a drop-in file validated by visudo
echo '%wheel ALL=(ALL:ALL) ALL' | sudo tee /etc/sudoers.d/10-wheel >/dev/null
sudo chmod 0440 /etc/sudoers.d/10-wheel
sudo visudo -c
```

### Enable SSH Daemon `[ROOT]`

```bash
# [ROOT] Enable OpenSSH server
sudo systemctl enable --now sshd
sudo ss -tlnp | grep sshd
```

### Install Hypervisor Guest Agents `[ROOT]`

```bash
# [ROOT] KVM / QEMU / Proxmox
sudo pacman -S --needed qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent

# [ROOT] VMware ESXi
sudo pacman -S --needed open-vm-tools
sudo systemctl enable --now vmtoolsd vmware-vmblock-fuse

# [ROOT] Hyper-V
sudo pacman -S --needed hyperv
sudo systemctl enable --now hv_fkvp_daemon hv_vss_daemon hv_fcopy_daemon
```

## AUR Helper Bootstrap

Build `paru` (Rust-based, reviews PKGBUILDs by default) or `yay` (Go-based) as a non-root user. `makepkg` refuses to run as `root`.

### Build `paru` `[NON-ROOT]`

```bash
# [NON-ROOT] Requires base-devel, git, and rust (or use paru-bin to skip Rust compilation)
git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
cd /tmp/paru-bin
less PKGBUILD
makepkg -si --noconfirm
cd ~ && rm -rf /tmp/paru-bin
```

### Build `yay` `[NON-ROOT]`

```bash
# [NON-ROOT] Prebuilt binary package skips Go toolchain download
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin
less PKGBUILD
makepkg -si --noconfirm
cd ~ && rm -rf /tmp/yay-bin
```

## Automated Maintenance Timers

Arch does not automatically prune `/var/cache/pacman/pkg/` or re-rank mirrors unless you enable the timers.

```bash
# [ROOT] Configure reflector timer parameters
sudo tee /etc/xdg/reflector/reflector.conf >/dev/null <<'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--latest 20
--fastest 15
--age 12
--sort rate
EOF

# Enable weekly package cache pruning (keeps last 3 versions), mirror refresh, and SSD TRIM
sudo systemctl enable --now paccache.timer
sudo systemctl enable --now reflector.timer
sudo systemctl enable --now fstrim.timer

# Confirm scheduled timers
systemctl list-timers --all | grep -E 'paccache|reflector|fstrim'
```
