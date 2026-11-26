# Windows Workstation Troubleshooting

Symptom-driven diagnostic matrix and recovery workflows for Windows 10/11 Pro/Enterprise workstations: `winget` source/install errors, OpenSSH and `ssh-agent` failures, locked files and runaway memory, networking/DNS/portproxy faults, Windows Update and component store corruption (`DISM`/`sfc`), and BSOD crash analysis.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Quick Matrix](#symptom-to-fix-quick-matrix)
- [winget and scoop Failures](#winget-and-scoop-failures)
- [OpenSSH Client and ssh-agent Troubleshooting](#openssh-client-and-ssh-agent-troubleshooting)
- [Locked Files, High CPU, and Invisible RAM Leaks](#locked-files-high-cpu-and-invisible-ram-leaks)
- [Networking, DNS, and PortProxy Diagnostics](#networking-dns-and-portproxy-diagnostics)
- [OS Corruption, Windows Update, and Explorer Crashes](#os-corruption-windows-update-and-explorer-crashes)
- [BSOD and Unexpected Reboot Analysis](#bsod-and-unexpected-reboot-analysis)
- [High-Signal Triage One-Liners](#high-signal-triage-one-liners)

## Symptom-to-Fix Quick Matrix

| Symptom | Primary Diagnostic Command | Root Cause / Fix |
| --- | --- | --- |
| `winget` fails with `0x8a15000f` or source timeout | `winget source list` | Corrupted winget index cache; run `winget source reset --force` and update App Installer |
| `git push` ignores `ssh-agent` and asks for passphrase | `git config --show-origin core.sshCommand` | Git is using bundled MSYS2 `ssh.exe`; point to `C:/Windows/System32/OpenSSH/ssh.exe` |
| `ssh-add` returns `Error connecting to agent` | `Get-Service ssh-agent` | Service disabled by default; `Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent` |
| File/folder cannot be deleted ("in use by another program") | `handle64.exe -accepteula "<path>"` | Identify owning PID and stop process or restart Explorer |
| RAM at 90% with low process totals in Task Manager | `RAMMap64.exe` (Use Counts tab) | Nonpaged Pool driver leak or WSL2/Hyper-V Driver Locked RAM; identify tag via `poolmon` or check `.wslconfig` |
| `netsh interface portproxy` rule forwards nothing | `Get-Service iphlpsvc` & `Get-NetFirewallRule` | `iphlpsvc` stopped, IPv6 disabled on loopback, or Windows Firewall blocking inbound port |
| System instability, Store crashes, or update error `0x80073701` | `DISM /Online /Cleanup-Image /CheckHealth` | WinSxS corruption; run `DISM /RestoreHealth` followed by `sfc /scannow` |
| Workstation BSODs intermittently | `Get-WinEvent -FilterHashtable @{LogName='System';Id=1001}` | Inspect `C:\Windows\Minidump\*.dmp` with WinDbg (`!analyze -v`) |

## winget and scoop Failures

### Repair winget Source Corruption or Missing Command `[ROOT]`

```powershell
# 1. Reset winget sources and re-sync catalogs
winget source reset --force
winget source update --accept-source-agreements

# 2. If winget command is missing or crashes with missing VCLibs/UI.Xaml, re-register App Installer
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

# 3. Inspect winget diagnostic logs for exact MSI/installer exit codes
Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 5 Name, LastWriteTime
```

### Repair scoop Shims or Broken PATH `[NON-ROOT]`

```powershell
# Run scoop built-in health check and reset broken package shims
scoop checkup
scoop reset *
```

## OpenSSH Client and ssh-agent Troubleshooting

`[NON-ROOT]` / `[ROOT]`
```powershell
# 1. Verify which ssh.exe is first in PATH (Windows native vs Git MSYS2)
Get-Command ssh, ssh-add -All | Select-Object Name, Source

# 2. Check ssh-agent service state and loaded keys
Get-Service ssh-agent | Select-Object Name, Status, StartType
ssh-add -L

# 3. Debug an SSH connection with full key-offer and config trace
ssh -vvv -G prod-bastion | Select-String "hostname|user|identityfile|proxyjump"
ssh -vvv prod-bastion

# 4. Fix "UNPROTECTED PRIVATE KEY FILE / Permissions are too open" on Windows NTFS
$key = "$env:USERPROFILE\.ssh\id_ed25519"
icacls.exe $key /inheritance:r
icacls.exe $key /grant:r "$($env:USERNAME):(R)"
icacls.exe $key /remove "NT AUTHORITY\Authenticated Users" "BUILTIN\Users" "Everyone"
```

> **Watch out:** If `icacls` shows `SYSTEM` or `Administrators` still listed on a user private key in `%USERPROFILE%\.ssh\id_ed25519`, Win32-OpenSSH accepts `SYSTEM` and `Administrators` alongside the key owner, but **rejects** any permission granted to `Users`, `Authenticated Users`, or `Everyone`. Always run `/inheritance:r` before granting explicit read access.

## Locked Files, High CPU, and Invisible RAM Leaks

### Find File Locks and Unresponsive Processes `[ROOT]`

```powershell
# 1. Identify which PID locks a file or directory
handle64.exe -accepteula -nobanner "C:\Projects\repo\target"

# 2. Inspect top 15 processes by RAM and CPU
Get-Process | Sort-Object WorkingSet64 -Descending |
    Select-Object -First 15 Name, Id, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,1)}}, CPU, Handles |
    Format-Table -AutoSize

# 3. Inspect Nonpaged Pool and Paged Pool usage (nonpaged > 1–2 GB strongly indicates a kernel driver leak)
Get-Counter '\Memory\Pool Nonpaged Bytes', '\Memory\Pool Paged Bytes', '\Memory\Available MBytes'
```

### Restart Frozen Shell/Taskbar Without Rebooting `[NON-ROOT]`

```powershell
# Cleanly restart Windows Explorer (fixes stuck taskbar, dead tray icons, hung file dialogs)
Stop-Process -Name explorer -Force
Start-Process explorer
```

## Networking, DNS, and PortProxy Diagnostics

`[ROOT]`
```powershell
# 1. Check active interfaces, default routes, and DNS servers
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Format-Table ifIndex, InterfaceAlias, NextHop, RouteMetric
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | Format-Table InterfaceAlias, ServerAddresses

# 2. Diagnose DNS resolution path (compares OS cache/NRPT vs querying a specific upstream)
Resolve-DnsName "api.internal.example.com"
Resolve-DnsName "api.internal.example.com" -Server 10.20.10.5

# 3. Troubleshoot failing netsh portproxy rules
Get-Service iphlpsvc | Select-Object Name, Status, StartType
netsh interface portproxy show all
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue

# 4. Reset corrupted Winsock/TCP-IP stack when VPN clients leave broken adapters [REBOOT]
# netsh winsock reset
# netsh int ip reset
```

> **Watch out:** `netsh interface portproxy` requires the **IP Helper** (`iphlpsvc`) service to be running and IPv6 enabled on the loopback/interface stack (`v4tov4` still depends on `iphlpsvc` initialization). If you disabled IPv6 via `DisabledComponents = 0xFF` in the registry, `portproxy` silently stops forwarding.

## OS Corruption, Windows Update, and Explorer Crashes

Run repairs in exact order: DISM component store first, then SFC protected files.

`[ROOT]`
```powershell
# 1. Repair WinSxS component store
DISM /Online /Cleanup-Image /RestoreHealth

# 2. Repair protected OS binaries using the clean WinSxS store
sfc /scannow

# 3. Inspect only actual repair/corruption lines from CBS.log
Select-String -Path "C:\Windows\Logs\CBS\CBS.log" -Pattern "\[SR\]" | Select-Object -Last 30

# 4. Reset stuck Windows Update cache
Stop-Service wuauserv, bits, cryptsvc -Force
Rename-Item "C:\Windows\SoftwareDistribution" "SoftwareDistribution.bak.$(Get-Date -Format yyyyMMddHHmm)"
Start-Service cryptsvc, bits, wuauserv
```

## BSOD and Unexpected Reboot Analysis

`[ROOT]`
```powershell
# 1. List recent BugCheck (1001), unexpected power loss (41), and forced shutdowns (6008)
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = 41, 1001, 6008
    StartTime = (Get-Date).AddDays(-30)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message | Format-Table -Wrap

# 2. Check for saved minidumps
Get-ChildItem "C:\Windows\Minidump\*.dmp" -ErrorAction SilentlyContinue |
    Select-Object Name, LastWriteTime, @{N='SizeKB';E={[math]::Round($_.Length/1KB,1)}}

# 3. Install WinDbg (Store/winget) and run automated crash triage from CLI
# winget install --id Microsoft.WinDbg --source winget
# cdb -z C:\Windows\Minidump\latest.dmp -c "!analyze -v; lmvm <faulting_module>; q"
```

## High-Signal Triage One-Liners

`[ROOT]`
```powershell
# Find which process owns a listening port (e.g., 3000 or 5432)
Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, State, OwningProcess, @{N='Process';E={(Get-Process -Id $_.OwningProcess).Name}}

# Check recent Application crashes (Event ID 1000) and hangs (Event ID 1002)
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = (Get-Date).AddDays(-3) } -MaxEvents 15 |
    Select-Object TimeCreated, Id, @{N='Summary';E={($_.Message -split "`n")[0..1] -join ' '}} | Format-Table -Wrap

# Inspect disk SMART health and wear status (NVMe/SATA)
Get-PhysicalDisk | Get-StorageReliabilityCounter |
    Select-Object DeviceId, Temperature, Wear, ReadErrorsTotal, WriteErrorsTotal

# List non-Microsoft kernel drivers currently loaded (fast BSOD suspect list)
Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' -and $_.PathName -notlike '*\System32\drivers\*' } |
    Select-Object Name, DisplayName, PathName | Format-Table -AutoSize

# Check boot time and uptime
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, LastBootUpTime
```
