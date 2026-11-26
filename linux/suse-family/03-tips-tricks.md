# openSUSE Family Tips and Tricks

High-leverage `zypper`, `snapper`, Btrfs, MicroOS `transactional-update`, and `/usr/etc` vendor-config workflows for openSUSE Leap, Tumbleweed, and MicroOS.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [`zypper` Server Tuning and Solver Workflows](#zypper-server-tuning-and-solver-workflows)
- [Master `/usr/etc` Vendor Configuration Separation](#master-usretc-vendor-configuration-separation)
- [Tuning `snapper` Quotas and Btrfs Maintenance](#tuning-snapper-quotas-and-btrfs-maintenance)
- [MicroOS Immutable Workflows (`--continue`, Podman Quadlets, `toolbox`)](#microos-immutable-workflows---continue-podman-quadlets-toolbox)
- [Kernel Retention and `purge-kernels`](#kernel-retention-and-purge-kernels)
- [Service Restarts After Library Upgrades (`zypper ps`)](#service-restarts-after-library-upgrades-zypper-ps)

## `zypper` Server Tuning and Solver Workflows

### Permanently Disable Recommended Packages on Servers `[ROOT]`

Prevent `zypper` from pulling optional GUI/docs/locale bloat on headless hosts by editing `/etc/zypp/zypp.conf`:

```bash
# [ROOT] Set solver.onlyRequires = true in /etc/zypp/zypp.conf
sudo sed -i 's/^# *solver.onlyRequires =.*/solver.onlyRequires = true/' /etc/zypp/zypp.conf
grep '^solver.onlyRequires' /etc/zypp/zypp.conf
```

### Enable Parallel Downloads and Faster Repo Refresh `[ROOT]`

```bash
# [ROOT] Tune concurrent downloads in /etc/zypp/zypp.conf (modern zypper)
sudo tee -a /etc/zypp/zypp.conf >/dev/null <<'EOF'
# Increase concurrent download streams
download.max_concurrent_connections = 8
EOF
```

### Cleanly Query Packages and Repo Changes `[NON-ROOT]`

```bash
# [NON-ROOT] List packages installed from non-default/orphaned repos (no repo owns them anymore)
zypper packages --orphaned

# [NON-ROOT] List packages installed from a specific repository (e.g., Packman or Docker CE)
zypper search --installed-only --repo docker-ce-stable

# [ROOT] Check security patches only (Leap)
sudo zypper list-patches --category security
sudo zypper patch --category security
```

## Master `/usr/etc` Vendor Configuration Separation

On openSUSE Tumbleweed and MicroOS, vendor defaults for `sshd`, `sudoers`, `nsswitch.conf`, `login.defs`, and `sysctl` live in `/usr/etc/` while local administrator overrides live in `/etc/`.

```bash
# [NON-ROOT] Inspect vendor defaults without modifying them
ls -la /usr/etc/ssh/
cat /usr/etc/nsswitch.conf

# [ROOT] Override cleanly by placing drop-ins in /etc/<service>.d/ or copying to /etc/
# Package upgrades update /usr/etc/ cleanly without generating .rpmnew conflicts
```

> **Watch out:** If `/etc/ssh/sshd_config` does not exist on Tumbleweed or MicroOS, SSH is reading `/usr/etc/ssh/sshd_config` (which automatically includes `/etc/ssh/sshd_config.d/*.conf`). Put local changes in `/etc/ssh/sshd_config.d/99-local.conf` rather than copying the entire vendor file.

## Tuning `snapper` Quotas and Btrfs Maintenance

Default `snapper` retention can fill small 20–30 GB cloud VM disks on Tumbleweed due to frequent rolling upgrades. Tighten quotas in `/etc/snapper/configs/root`:

```bash
# [ROOT] Restrict snapper to 5 number snapshots, disable hourly timeline snapshots on servers, and cap space at 25%
sudo snapper -c root set-config \
  SPACE_LIMIT=0.25 \
  FREE_LIMIT=0.2 \
  NUMBER_LIMIT=5 \
  NUMBER_LIMIT_IMPORTANT=5 \
  TIMELINE_CREATE=no

# Trigger immediate cleanup
sudo snapper cleanup number
sudo snapper cleanup timeline
sudo snapper list
```

### Verify Automated Btrfs Maintenance Timers `[ROOT]`

openSUSE ships `btrfsmaintenance` timers for periodic balance, scrub, and trim:

```bash
# [NON-ROOT] Check scheduled Btrfs health timers
systemctl list-timers --all | grep -E 'btrfs|snapper|fstrim'
```

> **Watch out:** Running heavy workloads (PostgreSQL, MariaDB, VM QCOW2 images) on copy-on-write Btrfs directories causes severe fragmentation unless CoW is disabled (`chattr +C /var/lib/pgsql`) on the empty directory before data files are written—or placed on a dedicated XFS/ext4 volume.

## MicroOS Immutable Workflows (`--continue`, Podman Quadlets, `toolbox`)

### Chaining Multiple Transactional Edits Without Rebooting `[ROOT]`

```bash
# [ROOT] First command creates a new snapshot
sudo transactional-update pkg in --no-recommends wireguard-tools

# Second command builds ON TOP of that pending snapshot instead of discarding it
sudo transactional-update --continue shell
```

### Prefer Podman Quadlets Over Host Package Installs `[ROOT]`

On MicroOS, run services inside rootless or rootful Podman containers managed natively by `systemd` via Quadlet `.container` unit files in `/etc/containers/systemd/`:

```ini
# /etc/containers/systemd/caddy.container
[Unit]
Description=Caddy Reverse Proxy
After=network-online.target

[Container]
Image=docker.io/library/caddy:2-alpine
AutoUpdate=registry
PublishPort=80:80
PublishPort=443:443
Volume=/srv/caddy/Caddyfile:/etc/caddy/Caddyfile:ro,Z
Volume=/srv/caddy/data:/data:Z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# [ROOT] Generate systemd unit from Quadlet and start
sudo systemctl daemon-reload
sudo systemctl start caddy.service
sudo systemctl enable --now podman-auto-update.timer
```

### Ad-Hoc Debugging Tools via `toolbox` `[NON-ROOT]`

Instead of installing compilers, `tcpdump`, or `nmap` into MicroOS's immutable rootfs, spin up an ephemeral Tumbleweed debug container with host namespaces:

```bash
# [NON-ROOT] Enter a privileged debug toolbox container (MicroOS)
toolbox -u
# Inside toolbox: zypper in tcpdump mtr bind-utils
```

## Kernel Retention and `purge-kernels`

Control how many fallback kernels openSUSE keeps in `/boot` via `/etc/zypp/zypp.conf`:

```ini
# /etc/zypp/zypp.conf
multiversion = provides:multiversion(kernel)
multiversion.kernels = latest,latest-1,running
```

```bash
# [ROOT] Manually prune old kernels immediately if /boot is tight
sudo systemctl start purge-kernels.service
rpm -qa kernel-default
```

## Service Restarts After Library Upgrades (`zypper ps`)

After updating `openssl`, `glibc`, or `systemd`, running services still map deleted old `.so` files in RAM until restarted.

```bash
# [ROOT] List only systemd service names holding deleted libraries
sudo zypper ps -sss

# [ROOT] Restart affected services cleanly (inspect the list first; exclude sshd/dbus if needed)
sudo zypper ps -s
```
