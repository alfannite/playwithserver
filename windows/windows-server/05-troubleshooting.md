# Windows Server Troubleshooting

Symptom-driven diagnostic matrix and incident workflows for Windows Server 2019, 2022, and 2025: OpenSSH failures, WinRM errors, Active Directory replication and time skew, IIS 500/503 outages, Hyper-V boot/network faults, Storage Spaces degradation, and Windows Update servicing corruption.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Quick Matrix](#symptom-to-fix-quick-matrix)
- [OpenSSH Key Authentication Failures](#openssh-key-authentication-failures)
- [WinRM and PowerShell Remoting Failures](#winrm-and-powershell-remoting-failures)
- [Active Directory, DNS, and Time Skew](#active-directory-dns-and-time-skew)
- [IIS 500, 502, and 503 Service Unavailable](#iis-500-502-and-503-service-unavailable)
- [Hyper-V VM Startup and Network Issues](#hyper-v-vm-startup-and-network-issues)
- [Storage Spaces Degraded Pools and Disk Exhaustion](#storage-spaces-degraded-pools-and-disk-exhaustion)
- [Windows Update and Component Store Repair](#windows-update-and-component-store-repair)
- [High-Signal Triage One-Liners](#high-signal-triage-one-liners)

## Symptom-to-Fix Quick Matrix

| Symptom | Primary Diagnostic Command | Root Cause / Fix |
| --- | --- | --- |
| SSH prompts for password despite valid key | `icacls C:\ProgramData\ssh\administrators_authorized_keys` | Inherited NTFS ACLs or UTF-8 BOM; reset ACLs to `Administrators:F` and `SYSTEM:F`, re-save ASCII |
| WinRM returns `WinRM cannot complete the operation` (0x80338119) | `Test-NetConnection <host> -Port 5986` and `Get-ChildItem WSMan:\localhost\Listener` | Missing HTTPS listener, expired cert, or firewall blocking TCP 5985/5986 |
| Kerberos auth fails with `KRB_AP_ERR_SKEW` | `w32tm /query /status` and `w32tm /stripchart /computer:dc01 /samples:5` | Clock drift >5 min; resync with `w32tm /resync /force` and fix Hyper-V time sync |
| Domain logon fails with `trust relationship failed` | `Test-ComputerSecureChannel -Verbose` | Machine password out of sync; run `Test-ComputerSecureChannel -Repair -Credential (Get-Credential)` |
| IIS returns `HTTP 503 Service Unavailable` | `& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list apppool` | AppPool stopped after rapid-fail crash or expired identity password; check `Application` + `System` (WAS) logs |
| Hyper-V VM fails to start with `0x80070005` Access Denied | `icacls "D:\Hyper-V\Virtual Hard Disks\vm.vhdx"` | Missing `NT VIRTUAL MACHINE\<VM-GUID>` NTFS permission; re-grant via `icacls` |
| Thin Storage Pool drops offline (`Detached`) | `Get-StoragePool` and `Get-VirtualDisk` | Physical pool hit 100% allocation; add disk or reclaim space via `Optimize-Volume -ReTrim` |
| Windows Update stuck or failing with `0x800f081f` / `0x80073701` | `DISM /Online /Cleanup-Image /CheckHealth` | Component store corruption; run `DISM /RestoreHealth` and reset `SoftwareDistribution` |

## OpenSSH Key Authentication Failures

When `ssh -vvv` shows the client offering your key and the server silently rejecting it, run `sshd` in foreground debug mode on an alternate port without interrupting production SSH on port 22.

`[ROOT]`
```powershell
# 1. Inspect recent OpenSSH operational log entries
Get-WinEvent -FilterHashtable @{ LogName = 'OpenSSH/Operational'; StartTime = (Get-Date).AddMinutes(-30) } |
    Select-Object TimeCreated, Id, Message | Format-Table -Wrap

# 2. Launch a temporary debug sshd instance on TCP 2222 (blocks terminal; Ctrl+C to stop)
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -d -p 2222

# 3. Verify permissions on administrators_authorized_keys and ssh_host_* private keys
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys"
icacls.exe "C:\ProgramData\ssh\ssh_host_ed25519_key"

# 4. Detect hidden UTF-8 BOM (first 3 bytes EF BB BF break sshd key parsing)
[System.IO.File]::ReadAllBytes("C:\ProgramData\ssh\administrators_authorized_keys")[0..2] |
    ForEach-Object { "{0:X2}" -f $_ }
```

Fix ACLs and rewrite cleanly without BOM:

`[ROOT]`
```powershell
$file = "C:\ProgramData\ssh\administrators_authorized_keys"
$lines = Get-Content $file
[System.IO.File]::WriteAllLines($file, $lines, [System.Text.UTF8Encoding]::new($false))
icacls.exe $file /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
Restart-Service sshd
```

## WinRM and PowerShell Remoting Failures

`[ROOT]`
```powershell
# 1. Verify WinRM service, active listeners, and bound certificate expiration
Get-Service WinRM
Get-ChildItem WSMan:\localhost\Listener | ForEach-Object {
    $thumb = (Get-Item "$($_.PSPath)\CertificateThumbprint" -ErrorAction SilentlyContinue).Value
    $cert = if ($thumb) { Get-ChildItem Cert:\LocalMachine\My\$thumb -ErrorAction SilentlyContinue }
    [PSCustomObject]@{
        Listener   = $_.Name
        Keys       = $_.Keys -join ', '
        Thumbprint = $thumb
        NotAfter   = $cert.NotAfter
    }
}

# 2. Check Windows Firewall profile (Public profile blocks WinRM by default)
Get-NetConnectionProfile | Format-Table Name, InterfaceAlias, NetworkCategory

# 3. Fix misclassified Public interface on a private management network
Set-NetConnectionProfile -InterfaceAlias "Ethernet0" -NetworkCategory Private

# 4. Test local WinRM stack end-to-end
Test-WSMan -ComputerName localhost
Test-WSMan -ComputerName localhost -UseSSL
```

> **Watch out:** On domain-joined servers after a reboot when the Domain Controller is unreachable, NLA (Network Location Awareness) can temporarily classify the NIC as `Public`, causing Windows Firewall to drop WinRM and RDP. Restarting `NlaSvc` (`Restart-Service NlaSvc -Force`) forces re-detection once the DC is reachable.

## Active Directory, DNS, and Time Skew

### Broken Secure Channel on a Member Server `[ROOT]`

```powershell
# Test trust relationship with Active Directory
Test-ComputerSecureChannel -Verbose

# Repair without disjoining/rejoining or rebooting
Test-ComputerSecureChannel -Repair -Credential (Get-Credential "CORP\DomainAdmin")
```

### Replication and DNS Diagnostics on a Domain Controller `[ROOT]`

```powershell
# 1. Identify failing replication partners and exact Win32 error codes
repadmin /showrepl * /errorsonly

# 2. Check SYSVOL / DFSR backlog and state (State 4 = Normal; 2 = Initial Sync)
Get-CimInstance -Namespace "root\MicrosoftDFS" -ClassName DfsrReplicatedFolderInfo |
    Select-Object ReplicatedFolderName, State

# 3. Verify DNS SRV records for the domain exist and resolve
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.corp.example.com

# 4. Measure real-time NTP offset against PDC Emulator
w32tm /stripchart /computer:dc01.corp.example.com /dataonly /samples:5
```

## IIS 500, 502, and 503 Service Unavailable

`[ROOT]`
```powershell
# 1. Check Application Pool states and recent WAS/W3SVC crash events
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list apppool
Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    ProviderName = 'Microsoft-Windows-WAS'
    StartTime    = (Get-Date).AddHours(-2)
} | Select-Object TimeCreated, Id, Message | Format-Table -Wrap

# 2. Inspect HTTP.sys URL reservations and SSL certificate bindings (catches port conflicts)
netsh http show servicestate view=requestq
netsh http show sslcert

# 3. Check latest IIS access logs for 500.x substatus codes (e.g., 500.19 = bad web.config, 500.30 = ASP.NET Core startup crash)
$latestLog = Get-ChildItem "C:\inetpub\logs\LogFiles\W3SVC1\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Select-String -Path $latestLog.FullName -Pattern " 500 | 502 | 503 " | Select-Object -Last 25

# 4. Restart a stopped AppPool after fixing identity password or web.config
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" start apppool /apppool.name:"ApiPool"
```

## Hyper-V VM Startup and Network Issues

`[ROOT]`
```powershell
# 1. Inspect Hyper-V Worker and VMMS operational logs for exact failure codes
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-Hyper-V-Worker-Admin', 'Microsoft-Windows-Hyper-V-VMMS-Admin'
    Level     = 1, 2
    StartTime = (Get-Date).AddHours(-2)
} -MaxEvents 20 | Select-Object TimeCreated, LogName, Id, Message | Format-Table -Wrap

# 2. Fix VHDX permission error (0x80070005 General Access Denied) after moving VHDX files
$vmId = (Get-VM -Name "srv-app-01").Id.Guid
icacls.exe "D:\Hyper-V\Virtual Hard Disks\srv-app-01.vhdx" /grant "NT VIRTUAL MACHINE\$($vmId):(F)"

# 3. Inspect virtual switch bindings and VLAN tagging when a VM loses connectivity
Get-VMNetworkAdapter -VMName "srv-app-01" | Format-List Name, SwitchName, MacAddress, Status, IPAddresses
Get-VMNetworkAdapterVlan -VMName "srv-app-01"
```

## Storage Spaces Degraded Pools and Disk Exhaustion

`[ROOT]`
```powershell
# 1. Locate unhealthy or retired physical disks
Get-PhysicalDisk | Where-Object HealthStatus -ne 'Healthy' |
    Format-Table FriendlyName, SerialNumber, SlotNumber, OperationalStatus, HealthStatus, Usage

# 2. Check pool physical allocation vs virtual disk footprint
Get-StoragePool -IsPrimordial $false |
    Select-Object FriendlyName, HealthStatus,
        @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}},
        @{N='AllocGB';E={[math]::Round($_.AllocatedSize/1GB,1)}},
        @{N='PctUsed';E={[math]::Round(($_.AllocatedSize/$_.Size)*100,1)}}

# 3. Reclaim deleted blocks on thin-provisioned NTFS/ReFS volumes
Optimize-Volume -DriveLetter D -ReTrim -Verbose

# 4. Replace a failed disk cleanly in a Storage Pool
# Step A: Mark failed disk retired
Set-PhysicalDisk -SerialNumber "S4X1NE0M123456" -Usage Retired
# Step B: Add replacement disk to pool
$newDisk = Get-PhysicalDisk -CanPool $true | Select-Object -First 1
Add-PhysicalDisk -StoragePoolFriendlyName "Pool-Data01" -PhysicalDisks $newDisk
# Step C: Rebuild redundancy and wait for completion before removing retired disk
Repair-VirtualDisk -FriendlyName "VD-HyperV"
Get-StorageJob
# Step D: Remove retired disk once repair finishes
Remove-PhysicalDisk -StoragePoolFriendlyName "Pool-Data01" -PhysicalDisks (Get-PhysicalDisk -SerialNumber "S4X1NE0M123456")
```

## Windows Update and Component Store Repair

`[ROOT]`
```powershell
# 1. Check and repair the Windows component store (WinSxS)
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth

# 2. If offline/air-gapped, point DISM to a matching install.wim ISO image
# DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:E:\sources\install.wim:2 /LimitAccess

# 3. Verify and repair protected OS binaries
sfc /scannow

# 4. Reset corrupted Windows Update download cache
Stop-Service wuauserv, bits, cryptsvc -Force
Rename-Item "C:\Windows\SoftwareDistribution" "SoftwareDistribution.old.$(Get-Date -Format yyyyMMddHHmm)"
Rename-Item "C:\Windows\System32\catroot2" "catroot2.old.$(Get-Date -Format yyyyMMddHHmm)"
Start-Service cryptsvc, bits, wuauserv

# 5. Generate readable WindowsUpdate.log on Desktop/Temp
Get-WindowsUpdateLog -LogPath "C:\Temp\WindowsUpdate.log"
```

> **Watch out:** Running `DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase` permanently removes superseded update payloads, which saves several GB on `C:` but prevents uninstalling any previously installed cumulative updates. Never run `/ResetBase` until a patch cycle has soaked cleanly in production.

## High-Signal Triage One-Liners

`[ROOT]`
```powershell
# Top 10 processes by Working Set RAM (MB)
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, Id, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,1)}}, CPU

# Top 10 processes by total CPU seconds
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, CPU, Threads

# Check all volumes with <15% free space
Get-Volume | Where-Object { $_.DriveLetter -and ($_.SizeRemaining / $_.Size) -lt 0.15 } |
    Select-Object DriveLetter, FileSystemLabel, @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}}, @{N='PctFree';E={[math]::Round(($_.SizeRemaining/$_.Size)*100,1)}}

# List all automatic services that are unexpectedly stopped (excluding delayed-start trigger services)
Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State!='Running'" |
    Select-Object Name, DisplayName, State, StartName

# Find which process holds a TCP port (e.g., 443)
Get-NetTCPConnection -LocalPort 443 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, State, OwningProcess, @{N='Process';E={(Get-Process -Id $_.OwningProcess).Name}}

# Check pending reboot flags across CBS, Windows Update, and PendingFileRenameOperations
[PSCustomObject]@{
    CBS             = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    WindowsUpdate   = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    FileRename      = [bool](Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
}
```
