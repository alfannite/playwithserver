# WSL2 Administration Tools

Essential Windows-side and Linux-side CLI tools for managing WSL2 instances: `wsl.exe` lifecycle and VHDX control, `usbipd-win` USB device passthrough, `Optimize-VHD` and `diskpart` VHDX compaction, `wslu` Windows interoperability utilities, and Docker Engine inside WSL2.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Tooling Overview Matrix](#tooling-overview-matrix)
- [WSL CLI Lifecycle and Maintenance](#wsl-cli-lifecycle-and-maintenance)
- [USB Passthrough with usbipd-win](#usb-passthrough-with-usbipd-win)
- [VHDX Compaction with Optimize-VHD and diskpart](#vhdx-compaction-with-optimize-vhd-and-diskpart)
- [Cross-OS Interop Tools wslu and win32yank](#cross-os-interop-tools-wslu-and-win32yank)
- [Native Docker Engine Inside WSL2](#native-docker-engine-inside-wsl2)

## Tooling Overview Matrix

| Tool | Runs On | Install Command | Primary Use Case |
| --- | --- | --- | --- |
| `wsl.exe` | Windows | `wsl --install` / `wsl --update` | Distro lifecycle, export/import, VHDX sparse toggle, shutdown |
| `usbipd-win` | Windows | `winget install --id dorssel.usbipd-win` | Attach physical USB serial adapters, YubiKeys, JTAG/ESP32 into WSL2 |
| `Optimize-VHD` | Windows (Pro/Ent) | Built into Hyper-V PowerShell module | Fast compaction of `ext4.vhdx` virtual disks |
| `diskpart` | Windows (All) | Built-in | Compact `ext4.vhdx` on Windows Home or systems without Hyper-V module |
| `wslu` | Linux (WSL2) | `sudo apt install wslu` | Open Windows browser (`wslview`), translate paths (`wslpath`) |
| `docker-ce` | Linux (WSL2) | Official Docker apt repo | Native container runtime without Docker Desktop licensing/overhead |

## WSL CLI Lifecycle and Maintenance

### Install `[ROOT]`

Built into Windows 10/11 via `wsl --install` and maintained via `wsl --update`.

### Real-World Usages `[NON-ROOT]`

```powershell
# 1. Inspect WSL engine version, kernel version, and running distributions
wsl --version
wsl --list --verbose

# 2. Run a one-off Linux command from PowerShell without entering an interactive shell
wsl -d Debian -- bash -lc "df -h / && uptime"

# 3. Export a point-in-time snapshot backup of a distribution to a compressed tarball or VHDX
wsl --export Debian "D:\Backups\debian-$(Get-Date -Format yyyyMMdd).tar"
wsl --export Debian "D:\Backups\debian-$(Get-Date -Format yyyyMMdd).vhdx" --vhd

# 4. Enable sparse VHD mode on an existing distro so deleted Linux blocks shrink ext4.vhdx automatically
wsl --shutdown
wsl --manage Debian --set-sparse true
```

> **Watch out:** Using `--set-sparse true` (`sparseVhd=true`) can occasionally trigger NTFS fragmentation or data-integrity warnings on older WSL builds (<2.0.9); keep `wsl --update` current and always keep periodic `wsl --export` backups of critical dev environments.

## USB Passthrough with usbipd-win

WSL2 runs inside a Hyper-V VM and cannot access physical USB ports natively. `usbipd-win` shares host USB devices over USB/IP directly into the WSL2 Linux kernel (which ships `vhci-hcd` built in on WSL 2.x).

### Install `[ROOT]`

```powershell
winget install --id dorssel.usbipd-win --exact --source winget --accept-package-agreements --accept-source-agreements
```

### Real-World Usages `[ROOT]` / `[NON-ROOT]`

```powershell
# 1. List all physical USB devices on Windows with their BUSID and sharing state
usbipd list

# 2. Bind a USB device once (requires elevated PowerShell [ROOT]; persists across reboots)
usbipd bind --busid 2-4

# 3. Attach the bound USB device into the running default WSL2 distro (no elevation needed once bound)
usbipd attach --wsl --busid 2-4

# 4. Auto-attach a flaky flashing device (e.g., ESP32/STM32 bootloader that resets USB) and detach when done
usbipd attach --wsl --auto-attach --busid 2-4
usbipd detach --busid 2-4
```

Verify inside Linux (`[NON-ROOT]`):

```bash
lsusb
dmesg | tail -n 20
ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

> **Watch out:** Attaching a USB device with `usbipd attach --wsl` exclusively disconnects it from Windows until you run `usbipd detach --busid <id>` or unplug it. Never bind/attach your primary USB keyboard, mouse, or USB Ethernet adapter unless you have alternate console access. If a Linux driver (like `ftdi_sio` or `cp210x`) is missing from the default Microsoft WSL2 kernel, check `zgrep CONFIG_USB_SERIAL /proc/config.gz`.

## VHDX Compaction with Optimize-VHD and diskpart

Even after deleting 40 GB of Docker images inside Linux, `ext4.vhdx` remains bloated on Windows NTFS unless sparse mode is active or you compact the virtual disk while WSL2 is shut down.

### Method 1: Optimize-VHD (Windows Pro/Enterprise with Hyper-V Module) `[ROOT]`

```powershell
# 1. Locate exact ext4.vhdx path for your distro from registry
Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    [PSCustomObject]@{ Distro = $p.DistributionName; BasePath = $p.BasePath }
}

# 2. Reclaim deleted blocks inside Linux first (optional, improves compaction yield)
wsl -d Debian -u root -- fstrim /

# 3. Shut down WSL2 completely so ext4.vhdx is unlocked
wsl --shutdown

# 4. Compact VHDX in Full mode
Optimize-VHD -Path "D:\WSL\Debian\ext4.vhdx" -Mode Full
```

### Method 2: diskpart (Works on Windows Home and Without Hyper-V Tools) `[ROOT]`

```powershell
wsl --shutdown

# Pipe scripted compaction commands directly to diskpart
@"
select vdisk file="D:\WSL\Debian\ext4.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@ | diskpart
```

> **Watch out:** Always run `wsl --shutdown` and verify `wsl --list --running` reports no active instances before compacting `ext4.vhdx`. Attempting to attach or compact an in-use VHDX fails with `The process cannot access the file because it is being used by another process`, or worse, risks ext4 journal corruption if forced.

## Cross-OS Interop Tools wslu and win32yank

Bridge Linux CLI tools cleanly with Windows browsers, clipboards, and Explorer paths.

### Install (Inside Debian/Ubuntu WSL2) `[ROOT]`

```bash
sudo apt update && sudo apt install -y wslu
```

### Real-World Usages `[NON-ROOT]`

```bash
# 1. Translate between Linux and Windows paths cleanly (built-in wslpath)
wslpath -w ~/projects/infra        # -> \\wsl.localhost\Debian\home\opsadmin\projects\infra
wslpath -u 'C:\Users\Admin\Downloads'  # -> /mnt/c/Users/Admin/Downloads

# 2. Open a URL or local HTML report in your default Windows browser
wslview https://github.com
wslview ./coverage/index.html

# 3. Copy Linux stdout to Windows clipboard and read Windows clipboard back into Linux
cat ~/.ssh/id_ed25519.pub | clip.exe
powershell.exe -NoProfile -Command Get-Clipboard | tr -d '\r'
```

> **Watch out:** Piping into `clip.exe` appends a Windows CRLF (`\r\n`) or preserves UTF-16 assumptions depending on locale, and `powershell.exe -Command Get-Clipboard` outputs `\r\n` line endings that break Linux shell scripts and SSH keys if not stripped with `tr -d '\r'`.

## Native Docker Engine Inside WSL2

With `systemd=true` enabled in `/etc/wsl.conf`, you can run standard Linux Docker CE natively inside WSL2 without installing Docker Desktop.

### Install (Inside Ubuntu/Debian WSL2) `[ROOT]`

```bash
# Install Docker CE from official Debian/Ubuntu repository
curl -fsSL https://get.docker.com | sudo sh

# Allow your non-root user to run docker commands without sudo
sudo usermod -aG docker "$USER"

# Enable and start dockerd via systemd
sudo systemctl enable --now docker
```

### Real-World Usages `[NON-ROOT]`

```bash
# 1. Verify native daemon and cgroups v2 support
docker info --format '{{.ServerVersion}} | CgroupVersion={{.CgroupVersion}}'

# 2. Run a container binding port 8080 (automatically reachable from Windows http://localhost:8080)
docker run --rm -d -p 8080:80 --name web nginx:alpine

# 3. Reclaim build cache and dangling image space before VHDX compaction
docker system df
docker system prune -af --volumes
```

> **Watch out:** If you previously installed **Docker Desktop** with WSL2 integration enabled, disable Docker Desktop's integration for this distro (or uninstall Docker Desktop) before installing native `docker-ce`—otherwise Docker Desktop overwrites `/usr/bin/docker` and `/var/run/docker.sock` with its proxy sockets on startup.
