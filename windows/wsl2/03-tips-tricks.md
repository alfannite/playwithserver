# WSL2 Tips and Tricks

Performance tuning and workflow optimizations for WSL2 on Windows 10/11: avoiding the `/mnt/c` I/O penalty, seamless Windows-to-WSL SSH agent forwarding, multi-distro management, memory reclamation tuning, GUI apps via WSLg, and deterministic startup scripts.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Cross-OS Filesystem Performance Rules](#cross-os-filesystem-performance-rules)
- [Share Windows ssh-agent Keys Inside WSL2](#share-windows-ssh-agent-keys-inside-wsl2)
- [Memory, Swap, and Sparse VHD Tuning](#memory-swap-and-sparse-vhd-tuning)
- [Running Multiple Isolated Distros and Cloning Templates](#running-multiple-isolated-distros-and-cloning-templates)
- [Windows Interop and VS Code Integration](#windows-interop-and-vs-code-integration)
- [Mirrored Networking and Localhost Tricks](#mirrored-networking-and-localhost-tricks)

## Cross-OS Filesystem Performance Rules

Accessing files across the Plan 9 (`9p` / `drvfs`) bridge between Windows NTFS (`/mnt/c`) and Linux `ext4` incurs severe metadata latency (10x–30x slower for `git status`, `npm install`, `cargo build`, or Docker bind mounts).

| Storage Location | Access Path (Linux) | Access Path (Windows) | Throughput & Latency | Recommended Use |
| --- | --- | --- | --- | --- |
| Native WSL2 `ext4.vhdx` | `~/projects/...` | `\\wsl.localhost\<Distro>\home\<user>\...` | Native ext4 speed (fast) | All Git repos, Docker volumes, Python/Node/Go/Rust builds |
| Windows NTFS (`drvfs`) | `/mnt/c/Users/...` | `C:\Users\...` | 10x–30x slower metadata I/O | Copying final build artifacts, reading single config files, Windows-only apps |

### Keep All Dev Workloads Inside Native ext4 `[NON-ROOT]`

```bash
# Always clone repos inside your Linux home directory, NOT /mnt/c
mkdir -p ~/src && cd ~/src
git clone git@github.com:org/infra.git

# Open the native Linux repo directly in Windows VS Code Remote-WSL (zero 9p penalty)
code ~/src/infra

# Open current native Linux directory in Windows File Explorer when needed
explorer.exe .
```

> **Watch out:** Never edit files inside `\\wsl.localhost\<Distro>` using legacy Windows tools that bypass the 9p server by modifying raw files inside `%LOCALAPPDATA%\Packages\...\rootfs` (older WSL1 habit). Always access Linux files from Windows strictly via `\\wsl.localhost\<Distro>\` or VS Code Remote-WSL.

## Share Windows ssh-agent Keys Inside WSL2

Reuse keys already stored in your Windows `ssh-agent` (or 1Password / hardware YubiKey on Windows) inside WSL2 without copying unencrypted private key files into Linux.

### Approach 1: Alias Windows ssh.exe for Simple Git/SSH `[NON-ROOT]`

Inside WSL2 `~/.bashrc` or `~/.zshrc`:

```bash
# Use native Windows ssh.exe directly for git so Windows ssh-agent handles auth transparently
git config --global core.sshCommand "ssh.exe"
```

### Approach 2: Full UNIX Socket Bridge via npiperelay + socat `[NON-ROOT]`

Needed for Ansible, Terraform, `ssh-add -L`, and native Linux `ssh` inside WSL2.

Install `npiperelay` on Windows (`[NON-ROOT]`):

```powershell
winget install --id albertony.npiperelay --source winget --accept-package-agreements --accept-source-agreements
```

Install `socat` inside WSL2 (`[ROOT]`) and bridge the Windows named pipe in `~/.bashrc`:

```bash
sudo apt install -y socat
```

Add to `~/.bashrc` (`[NON-ROOT]`):

```bash
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
if ! ss -a 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
    rm -f "$SSH_AUTH_SOCK"
    (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &) >/dev/null 2>&1
fi
```

Verify inside WSL2:

```bash
ssh-add -L
```

## Memory, Swap, and Sparse VHD Tuning

### Choose the Right autoMemoryReclaim Mode in .wslconfig

| `autoMemoryReclaim` Mode | Behavior | Best For |
| --- | --- | --- |
| `gradual` | Slowly reclaims cached memory after 5 minutes of low CPU | General development workstations (balanced performance + RAM savings) |
| `dropcache` | Immediately drops Linux page cache when idle | Tight RAM laptops (16 GB) running heavy Windows apps alongside WSL2 |
| `disabled` | Retains Linux page cache up to `memory=` limit | High-RAM workstations (64 GB+) running continuous builds/databases |

### Trigger Immediate Manual Cache Drop Without Shutting Down WSL2 `[ROOT]`

```bash
# Flush Linux page cache cleanly inside WSL2 (triggers WSL2 host memory reclaim)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
```

### Sparse VHD Trade-offs

Enabling `sparseVhd=true` in `.wslconfig` (or `wsl --manage <Distro> --set-sparse true`) lets Windows shrink `ext4.vhdx` automatically after `fstrim` or file deletion, eliminating most manual `Optimize-VHD` runs. Trade-offs:
- Slightly higher NTFS fragmentation on spinning disks (negligible on NVMe SSDs).
- Requires modern WSL2 (`>= 2.0.9`) to avoid early sparse-VHD corruption bugs.

## Running Multiple Isolated Distros and Cloning Templates

Clone a clean golden base distro in seconds to isolate client engagements, Kubernetes clusters, or risky package experiments.

`[NON-ROOT]`
```powershell
# 1. Export a freshly updated base Debian image once as a reusable golden template
wsl --shutdown
wsl --export Debian "D:\WSL\Templates\debian-12-base.tar"

# 2. Spin up isolated project environments from the golden template
New-Item -ItemType Directory -Path "D:\WSL\lab-k8s", "D:\WSL\client-alpha" -Force | Out-Null
wsl --import lab-k8s "D:\WSL\lab-k8s" "D:\WSL\Templates\debian-12-base.tar" --version 2
wsl --import client-alpha "D:\WSL\client-alpha" "D:\WSL\Templates\debian-12-base.tar" --version 2

# 3. Launch a specific isolated distro directly
wsl -d lab-k8s
```

> **Watch out:** All running WSL2 distributions share the **same** Linux kernel, RAM pool, and virtual network namespace inside one lightweight Hyper-V utility VM. Stopping one distro (`wsl --terminate lab-k8s`) frees its processes, while `wsl --shutdown` terminates all running distros and stops the shared VM.

## Windows Interop and VS Code Integration

### Launch Linux Pipelines from PowerShell and Vice Versa `[NON-ROOT]`

```powershell
# Pipe PowerShell output directly through Linux jq/grep/awk
Get-Process | ConvertTo-Json | wsl jq -r '.[] | select(.WorkingSet64 > 200000000) | .ProcessName' | Sort-Object -Unique
```

```bash
# Inside WSL2, call Windows binaries seamlessly for hardware/host visibility
ipconfig.exe /all | grep -E "adapter|IPv4|DNS Servers"
powershell.exe -NoProfile -Command "Get-NetConnectionProfile | Format-Table Name, NetworkCategory"
```

### Clean Git Line Endings Across Windows and WSL2 `[NON-ROOT]`

Prevent Windows CRLF corruption in shell scripts (`^M` / `\r` errors):

```bash
# Inside WSL2 Linux: always check out LF and convert accidental CRLF on commit
git config --global core.autocrlf input
```

## Mirrored Networking and Localhost Tricks

With `networkingMode=mirrored` in `%USERPROFILE%\.wslconfig`:
- Linux sees the **exact same IP addresses** as your Windows host NICs (including corporate VPN interfaces).
- Services listening on `0.0.0.0:8080` inside Linux are immediately accessible on the host LAN IP (subject to Windows Hyper-V Firewall rules) without manual `netsh interface portproxy` forwarding.
- With `hostAddressLoopback=true` under `[experimental]`, Linux containers can reach Windows services bound to `127.0.0.1` (e.g., a local Windows SQL Server or corporate proxy) directly at `127.0.0.1` instead of finding the NAT gateway IP.
