# WSL2 Bootstrap

First-boot provisioning for Windows Subsystem for Linux 2 (WSL2) on Windows 10/11: enabling the WSL2 kernel and Store distribution engine, configuring global `%USERPROFILE%\.wslconfig`, per-distro `/etc/wsl.conf` with `systemd`, moving distributions to a secondary drive (`D:`), and verifying clock, network, and DNS integration.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Enable WSL2 and Update Kernel](#enable-wsl2-and-update-kernel)
- [Install a Linux Distribution](#install-a-linux-distribution)
- [Global Host Configuration with .wslconfig](#global-host-configuration-with-wslconfig)
- [Per-Distro Configuration with /etc/wsl.conf](#per-distro-configuration-with-etcwslconf)
- [Relocate Distro Storage to D Drive](#relocate-distro-storage-to-d-drive)
- [Post-Bootstrap Verification](#post-bootstrap-verification)

## Enable WSL2 and Update Kernel

Ensure CPU virtualization (Intel VT-x / AMD-V) is enabled in UEFI/BIOS, then install the Store-packaged WSL2 runtime and latest Linux kernel.

`[ROOT]` `[REBOOT]`
```powershell
# Install WSL2 runtime + VirtualMachinePlatform + default distro (or use --no-distribution to pick manually)
wsl --install --no-distribution

# Reboot Windows to initialize the Hyper-V virtual machine platform
Restart-Computer
```

After reboot, update to the latest WSL2 engine and enforce WSL2 as the default version:

`[ROOT]`
```powershell
# Update WSL2 engine and Microsoft Linux kernel to the latest GitHub/Store release
wsl --update

# Confirm WSL2 version (2.x required for mirrored networking, dnsTunneling, and autoMemoryReclaim)
wsl --version
wsl --set-default-version 2
```

## Install a Linux Distribution

List official distributions and install your preferred server-matched base image (Ubuntu LTS or Debian).

`[NON-ROOT]`
```powershell
# List available online distributions
wsl --list --online

# Install Debian or Ubuntu 24.04 LTS
wsl --install -d Debian
# Or: wsl --install -d Ubuntu-24.04

# List installed distributions, running state, and WSL version
wsl --list --verbose
```

During first launch, create your non-root UNIX username and password, then update base packages inside Linux:

`[ROOT]`
```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y ca-certificates curl git gnupg iproute2 dnsutils jq ripgrep tmux
```

## Global Host Configuration with .wslconfig

`%USERPROFILE%\.wslconfig` controls the single shared lightweight utility VM that hosts **all** WSL2 distributions. Without it, WSL2 can consume up to 50% of host RAM and never release cached page memory cleanly under older defaults.

`[NON-ROOT]`
```powershell
@'
[wsl2]
# Cap VM RAM and vCPU count to prevent host starvation (adjust to ~50% of host RAM max)
memory=8GB
processors=4
swap=2GB
localhostForwarding=true

# Modern Windows 11 22H2+ (WSL 2.0+) networking: mirrors host interfaces, fixes VPN routing & localhost binding
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true

[experimental]
# Gradually return idle Linux page cache to Windows host (options: gradual | dropcache | disabled)
autoMemoryReclaim=gradual

# Automatically shrink ext4.vhdx when files are deleted inside Linux (reduces manual compaction)
sparseVhd=true

# Allow containers/services inside WSL2 to bind to host loopback seamlessly in mirrored mode
hostAddressLoopback=true
'@ | Set-Content -Path "$env:USERPROFILE\.wslconfig" -Encoding ascii
```

Apply `.wslconfig` changes by shutting down the WSL2 VM completely:

`[NON-ROOT]`
```powershell
wsl --shutdown
```

> **Watch out:** `networkingMode=mirrored`, `dnsTunneling=true`, `autoProxy=true`, and `firewall=true` require **Windows 11 22H2 (Build 22621+) with WSL 2.0.0+**. On Windows 10, WSL2 silently ignores `networkingMode=mirrored` and stays in NAT mode—check `wsl --version` before relying on mirrored networking features. Also avoid saving `.wslconfig` with Windows PowerShell 5.1 `-Encoding utf8` (which writes a UTF-8 BOM that breaks parsing of the `[wsl2]` header).

## Per-Distro Configuration with /etc/wsl.conf

`/etc/wsl.conf` resides **inside each Linux distribution** and governs boot init (`systemd`), Windows drive mount permissions, Windows binary interoperability, and `/etc/resolv.conf` behavior.

`[ROOT]`
```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true

[automount]
enabled=true
root=/mnt/
# metadata enables chmod/chown on /mnt/c; umask=22,fmask=11 prevents all Windows files showing as 0777 executable
options="metadata,umask=22,fmask=11"
mountFsTab=true

[interop]
enabled=true
appendWindowsPath=true

[network]
generateHosts=true
generateResolvConf=true

[user]
default=opsadmin
EOF
```

Terminate the distro from PowerShell so `/etc/wsl.conf` takes effect on next boot:

`[NON-ROOT]`
```powershell
wsl --terminate Debian
wsl -d Debian
```

> **Watch out:** Setting `appendWindowsPath=false` speeds up shell startup and prevents accidentally executing Windows `.exe` shims, but breaks launching VS Code (`code .`) or Windows Explorer (`explorer.exe .`) from WSL unless you explicitly add `/mnt/c/Users/<user>/AppData/Local/Programs/Microsoft VS Code/bin` to your Linux `$PATH`.

## Relocate Distro Storage to D Drive

By default, WSL2 stores `ext4.vhdx` inside `%LOCALAPPDATA%\Packages\<Distro>\LocalState\`, which rapidly fills a small `C:` SSD when running Docker builds or large repos. Export and re-import to `D:\WSL\`:

`[NON-ROOT]`
```powershell
# 1. Stop all running WSL instances to guarantee a clean filesystem export
wsl --shutdown

# 2. Export existing distribution to a tarball
New-Item -ItemType Directory -Path "D:\WSL\Export", "D:\WSL\Debian" -Force | Out-Null
wsl --export Debian "D:\WSL\Export\debian-clean.tar"

# 3. Unregister the C: copy [DESTRUCTIVE to the C: copy only after verifying the tar exists]
Test-Path "D:\WSL\Export\debian-clean.tar"
wsl --unregister Debian

# 4. Import into D:\WSL\Debian as a WSL2 VHDX
wsl --import Debian "D:\WSL\Debian" "D:\WSL\Export\debian-clean.tar" --version 2

# 5. Set default distribution and verify default user is set in /etc/wsl.conf
wsl --set-default Debian
wsl -d Debian -u root -- grep -A2 '^\[user\]' /etc/wsl.conf

# 6. Remove temporary export archive once verified
Remove-Item "D:\WSL\Export\debian-clean.tar"
```

> **Watch out:** After `wsl --import`, WSL2 resets the default login user to `root` even if your user existed prior to export. Always configure `[user] default=<username>` inside `/etc/wsl.conf` (and restart the distro via `wsl --terminate <Distro>`), otherwise every terminal tab opens as `root`.

## Post-Bootstrap Verification

Run inside the Linux distribution:

`[NON-ROOT]`
```bash
# 1. Confirm systemd is PID 1 and running cleanly
ps -p 1 -o comm=
systemctl is-system-running

# 2. Confirm memory cap, CPU count, and kernel version
free -h
nproc
uname -r

# 3. Confirm mirrored networking / IP address and external DNS resolution
ip -br addr
dig +short github.com

# 4. Confirm native ext4 home vs /mnt/c mount options
df -hT ~ /mnt/c
mount | grep drvfs
```
