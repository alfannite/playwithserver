# Windows Workstation Tips and Tricks

Admin workflow optimizations and OS-level tricks for Windows 10/11 Pro/Enterprise: Windows Terminal profiles, PowerShell 7 shortcuts, clipboard/credential management, virtual network & DNS speedups, SSD/storage maintenance, and power/hibernation tuning.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [PowerShell 7 and Windows Terminal Productivity](#powershell-7-and-windows-terminal-productivity)
- [SSH Config, ProxyJump, and Multi-Host Multiplexing](#ssh-config-proxyjump-and-multi-host-multiplexing)
- [Windows Credential Manager and Secrets CLI](#windows-credential-manager-and-secrets-cli)
- [Network, DNS, and Split-VPN Tricks](#network-dns-and-split-vpn-tricks)
- [Storage, WinSxS, and Pagefile Hygiene](#storage-winsxs-and-pagefile-hygiene)
- [System Diagnostics and Hidden Built-in Tools](#system-diagnostics-and-hidden-built-in-tools)

## PowerShell 7 and Windows Terminal Productivity

### Quake Mode and Split Panes in Windows Terminal `[NON-ROOT]`

Windows Terminal includes a built-in drop-down Quake console (`Win + \`` when launched with `wt -w _quake`). Keybindings to memorize:

| Shortcut | Action |
| --- | --- |
| `Alt + Shift + D` | Auto-split active pane vertically/horizontally |
| `Alt + Shift + Plus` / `Minus` | Explicit vertical / horizontal pane split |
| `Alt + Arrow Keys` | Navigate between panes |
| `Ctrl + Shift + W` | Close active pane |
| `Ctrl + Shift + P` | Open Command Palette (broadcast input, export buffer, rename tab) |

### Run Commands Elevated from a Standard Shell Using gsudo `[NON-ROOT]`

Instead of opening a separate Administrator window for single privileged commands, install `gsudo` (`sudo`-like elevation in the same terminal tab):

```powershell
winget install --id gerardog.gsudo --source winget --accept-package-agreements --accept-source-agreements

# Run a single elevated PowerShell command inline without losing your current directory
gsudo Restart-Service ssh-agent
gsudo { Get-NetFirewallRule -Direction Inbound -Enabled True | Measure-Object }
```

> **Watch out:** Windows 11 24H2 ships a native `sudo.exe` (`Settings -> System -> For developers -> Enable sudo`), configured to run inline (`sudo config --enable normal`). Avoid aliasing both native `sudo` and `gsudo` simultaneously unless you explicitly pick one to avoid surprising UAC behavior.

### Inspect Command Objects and Clipboard Piping `[NON-ROOT]`

```powershell
# Pipe any output directly to Windows clipboard (built-in Set-Clipboard / scb)
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard

# Read clipboard directly into PowerShell pipeline (e.g., parse copied JSON)
Get-Clipboard | ConvertFrom-Json

# Open current directory in File Explorer or VS Code instantly
ii .       # Invoke-Item .
code .
```

## SSH Config, ProxyJump, and Multi-Host Multiplexing

Store structured host aliases in `%USERPROFILE%\.ssh\config` so `ssh`, `scp`, `sftp`, and VS Code Remote-SSH share identical settings.

`[NON-ROOT]`
```sshconfig
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    IdentitiesOnly yes
    AddKeysToAgent yes

Host prod-bastion
    HostName 198.51.100.20
    User opsadmin
    IdentityFile ~/.ssh/id_ed25519

Host 10.20.*
    User opsadmin
    ProxyJump prod-bastion
    IdentityFile ~/.ssh/id_ed25519
```

> **Watch out:** OpenSSH `ControlMaster` / `ControlPersist` Unix domain socket multiplexing is **not** supported reliably on Win32-OpenSSH (`ssh.exe`). If you copy a Linux `~/.ssh/config` containing `ControlMaster auto` and `ControlPath ~/.ssh/cm-%r@%h:%p`, remove or guard those lines on Windows, otherwise connections fail with `getsockname failed` or `mux_client_request_session` errors.

## Windows Credential Manager and Secrets CLI

Manage cached SMB, RDP, and Git credentials from the command line using `cmdkey` instead of hunting through Control Panel.

`[NON-ROOT]`
```powershell
# List all stored generic and domain credentials
cmdkey /list

# Pre-stage credentials for an administrative SMB share or RDP host
cmdkey /add:srv-file-01.corp.example.com /user:CORP\opsadmin /pass:*

# Delete stale cached credentials causing SMB "Multiple connections to a server" errors
cmdkey /delete:srv-file-01.corp.example.com
```

## Network, DNS, and Split-VPN Tricks

### View and Flush Local DNS Cache with TTLs `[NON-ROOT]`

```powershell
# Inspect cached DNS records and remaining TTL (far cleaner than ipconfig /displaydns)
Get-DnsClientCache | Format-Table Entry, Type, Status, TimeToLive, Data -AutoSize

# Flush local DNS resolver cache
Clear-DnsClientCache
```

### Set Interface Metric So Local LAN Beats VPN Default Route `[ROOT]`

When a corporate VPN hijacks local homelab or subnet traffic, inspect interface metrics and pin your physical NIC or VPN adapter cleanly:

```powershell
# Inspect current IPv4 interface metrics (lower number = higher priority)
Get-NetIPInterface -AddressFamily IPv4 | Sort-Object InterfaceMetric |
    Format-Table ifIndex, InterfaceAlias, InterfaceMetric, Dhcp, ConnectionState

# Force DNS suffix routing rules via NRPT (Name Resolution Policy Table) for internal domains
Add-DnsClientNrptRule -Namespace ".lab.internal" -NameServers "10.20.10.5"
Get-DnsClientNrptRule
```

### Quick One-Line HTTP/TLS Certificate Inspector in PowerShell `[NON-ROOT]`

Check expiration date, issuer, and SANs of any remote HTTPS endpoint without needing `openssl`:

```powershell
function Get-TlsCert($TargetHost, $Port = 443) {
    $tcp = [System.Net.Sockets.TcpClient]::new($TargetHost, $Port)
    $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, { $true })
    $ssl.AuthenticateAsClient($TargetHost)
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
    $ssl.Dispose(); $tcp.Dispose()
    $cert | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint
}
Get-TlsCert "github.com"
```

## Storage, WinSxS, and Pagefile Hygiene

### Reclaim Disk Space Safely on Dev Workstations `[ROOT]`

```powershell
# 1. Disable hibernation file (hiberfil.sys) on desktops/always-plugged-in workstations (saves 12–32 GB)
powercfg /hibernate off
# Or keep Fast Startup with reduced hiberfil.sys size (40% of RAM):
# powercfg /h /type reduced

# 2. Check and clean WinSxS superseded components
DISM /Online /Cleanup-Image /AnalyzeComponentStore
DISM /Online /Cleanup-Image /StartComponentCleanup

# 3. Inspect large folders quickly in PowerShell without installing third-party tools
Get-ChildItem C:\ -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $bytes = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    [PSCustomObject]@{ Folder = $_.FullName; SizeGB = [math]::Round($bytes / 1GB, 2) }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize
```

### Add Defender Exclusions for Local Dev Build Directories Only `[ROOT]`

Real-time antivirus scanning of `node_modules`, Rust `target/`, Go module caches, and `.git` objects slows builds by 2–5x. Use **Dev Drive** (ReFS volume with Defender Performance Mode on Windows 11 23H2+) or narrow folder exclusions strictly to trusted build output caches—never exclude `Downloads` or `C:\Users`.

```powershell
# Narrow exclusion for Rust/Cargo and Go build caches only (never exclude general user folders)
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.cargo", "$env:USERPROFILE\go\pkg"
```

## System Diagnostics and Hidden Built-in Tools

| Command | Tool | What It Reveals |
| --- | --- | --- |
| `powercfg /batteryreport /output C:\Temp\battery.html` | Battery Report | Design vs full-charge capacity, wear level, standby drain |
| `powercfg /sleepstudy /output C:\Temp\sleep.html` | Modern Standby Study | Which driver or app drained battery during sleep |
| `perfmon /rel` | Reliability Monitor | Visual timeline of app crashes, driver installs, BSODs |
| `perfmon /report` | System Diagnostics Report | 60-second CPU, disk, network, and service health audit |
| `pktmon comp list` | Packet Monitor | Inspects packet drops across virtual switches, NICs, and filters |
| `bcdedit /enum` | Boot Configuration Data | Hypervisor launch type (`hypervisorlaunchtype Auto`), boot entries |
