# Windows Administration Hub

Operational reference for Windows Server, Windows 10/11 Pro workstations, and WSL2 environments using PowerShell 7, native CIM/WMI, OpenSSH, and Sysinternals.

[← Home](../README.md)

## Variant Guides

| Variant | Target Environment | 01 Bootstrap | 02 Tools | 03 Tips & Tricks | 04 Hardening | 05 Troubleshooting |
| --- | --- | --- | --- | --- | --- | --- |
| `windows-server` | Windows Server 2019/2022/2025 (Core & Desktop) | [Bootstrap](windows-server/01-bootstrap.md) | [Tools](windows-server/02-tools.md) | [Tips & Tricks](windows-server/03-tips-tricks.md) | [Hardening](windows-server/04-hardening.md) | [Troubleshooting](windows-server/05-troubleshooting.md) |
| `windows-workstation` | Windows 10/11 Pro/Enterprise admin jumpbox | [Bootstrap](windows-workstation/01-bootstrap.md) | [Tools](windows-workstation/02-tools.md) | [Tips & Tricks](windows-workstation/03-tips-tricks.md) | [Hardening](windows-workstation/04-hardening.md) | [Troubleshooting](windows-workstation/05-troubleshooting.md) |
| `wsl2` | WSL2 Linux guests on Windows 10/11 | [Bootstrap](wsl2/01-bootstrap.md) | [Tools](wsl2/02-tools.md) | [Tips & Tricks](wsl2/03-tips-tricks.md) | [Hardening](wsl2/04-hardening.md) | [Troubleshooting](wsl2/05-troubleshooting.md) |

## Shell and Environment Selection

| Environment | Shell / Binary | Best Used For | Key Limitation |
| --- | --- | --- | --- |
| PowerShell 7+ (`pwsh`) | `pwsh.exe` | Cross-platform scripting, parallel `ForEach-Object -Parallel`, modern modules, JSON/REST APIs | Some legacy Windows Server modules require `-UseWindowsPowerShell` compatibility layer |
| Windows PowerShell 5.1 | `powershell.exe` | Built-in Server Core modules (`ServerManager`, older AD/IIS/Hyper-V cmdlets) | Frozen feature set; slower pipeline; UTF-16LE default redirection (`Out-File`) |
| Command Prompt (`cmd`) | `cmd.exe` | Legacy batch wrappers, quick `mklink`, `icacls`, `bcdedit`, `netsh` invocations | Text-only parsing; fragile escaping |
| WSL2 (`wsl.exe`) | Native Linux ELF inside lightweight Hyper-V utility VM | Linux CLI toolchains (`jq`, `awk`, `ssh`, `ansible`, `kubectl`, Docker Engine) | Cross-filesystem I/O (`/mnt/c`) is dramatically slower than native ext4 (`~`) |

## Modern PowerShell vs Legacy CMD Translation

| Task | Modern PowerShell (Preferred) | Legacy CMD / Utility |
| --- | --- | --- |
| Listening TCP ports & owning PID | `Get-NetTCPConnection -State Listen \| Select LocalAddress,LocalPort,OwningProcess` | `netstat -ano` |
| IP addresses & interfaces | `Get-NetIPAddress -AddressFamily IPv4` | `ipconfig /all` |
| Routing table | `Get-NetRoute -AddressFamily IPv4` | `route print` |
| DNS query | `Resolve-DnsName example.com -Type AAAA` | `nslookup example.com` |
| Port reachability test | `Test-NetConnection -ComputerName 10.0.0.10 -Port 443` | `telnet 10.0.0.10 443` |
| Firewall rules | `Get-NetFirewallRule -Enabled True` | `netsh advfirewall firewall show rule name=all` |
| Services | `Get-Service`, `Restart-Service` | `sc query`, `net start` |
| Disks & volumes | `Get-Disk`, `Get-Partition`, `Get-Volume` | `diskpart` |
| Event Logs | `Get-WinEvent -FilterHashtable @{LogName='System'; Level=2}` | `wevtutil qe System` |
| System hardware / OS info | `Get-CimInstance Win32_OperatingSystem` | `wmic os get *` (deprecated/removed in Win11 24H2) |

> **Watch out:** `wmic.exe` is removed in Windows 11 24H2 and Windows Server 2025. Always use `Get-CimInstance` instead of `wmic` or the older DCOM-based `Get-WmiObject` (which is unavailable in PowerShell 7).

## Related Scripts

- [scripts/windows/windows-ops-bootstrap.ps1](../scripts/windows/windows-ops-bootstrap.ps1) — Install PowerShell 7, Git, Sysinternals, and admin CLI packages via `winget`
- [scripts/windows/wsl2-compact-vhdx.ps1](../scripts/windows/wsl2-compact-vhdx.ps1) — Safely shut down WSL2 and reclaim unused space from `ext4.vhdx`
