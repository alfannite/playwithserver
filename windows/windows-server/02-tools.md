# Windows Server Core Administration Tools

Production CLI reference for Windows Server 2019, 2022, and 2025: Hyper-V management, Active Directory and RSAT diagnostics, IIS administration, Storage Spaces, modern networking, Event Log querying, and WinRM operations.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Tooling Overview Matrix](#tooling-overview-matrix)
- [Hyper-V Management CLI](#hyper-v-management-cli)
- [Active Directory and RSAT Diagnostics](#active-directory-and-rsat-diagnostics)
- [IIS Administration](#iis-administration)
- [Storage Spaces and Disk Management](#storage-spaces-and-disk-management)
- [Modern Networking and Firewall](#modern-networking-and-firewall)
- [Event Logs with Get-WinEvent](#event-logs-with-get-winevent)
- [WinRM and Remote Sessions](#winrm-and-remote-sessions)

## Tooling Overview Matrix

| Domain | Modern Tool / Module | Legacy Tool to Avoid | Installation Command |
| --- | --- | --- | --- |
| Hyper-V | `Hyper-V` PowerShell module | Hyper-V Manager GUI only | `Install-WindowsFeature Hyper-V-PowerShell` |
| Active Directory | `ActiveDirectory`, `dcdiag`, `repadmin`, `nltest` | `dsquery` / `dsget` | `Install-WindowsFeature RSAT-AD-Tools` |
| IIS | `IISAdministration`, `appcmd.exe` | `WebAdministration` (5.1-bound), `adsutil.vbs` | `Install-WindowsFeature Web-Mgmt-Tools` |
| Storage | `Storage` module (`Get-StoragePool`, `New-VirtualDisk`) | `diskpart` (for scripted pools) | Built-in |
| Network Sockets | `Get-NetTCPConnection`, `Test-NetConnection` | `netstat`, `telnet` | Built-in |
| System Inventory | `Get-CimInstance` | `wmic`, `Get-WmiObject` | Built-in |
| Event Logs | `Get-WinEvent` | `Get-EventLog` | Built-in |

## Hyper-V Management CLI

Manage virtual switches, VM lifecycle, checkpoints, exports, and VHDX compaction entirely from PowerShell without GUI overhead.

### Install `[ROOT]`

```powershell
# Install Hyper-V PowerShell management module (without hypervisor role) or full role
Install-WindowsFeature -Name Hyper-V-PowerShell
# Full role on host:
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

### Real-World Usages `[ROOT]`

```powershell
# 1. Provision a Generation 2 VM with Secure Boot (Linux template) and dynamic VHDX
New-VM -Name "deb-app-01" `
    -MemoryStartupBytes 4GB `
    -Generation 2 `
    -NewVHDPath "D:\Hyper-V\Virtual Hard Disks\deb-app-01.vhdx" `
    -NewVHDSizeBytes 60GB `
    -SwitchName "vSwitch-External"
Set-VMProcessor -VMName "deb-app-01" -Count 4
Set-VMMemory -VMName "deb-app-01" -DynamicMemoryEnabled $false
Set-VMFirmware -VMName "deb-app-01" -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
Add-VMDvdDrive -VMName "deb-app-01" -Path "D:\ISO\debian-12.iso"
Start-VM -Name "deb-app-01"

# 2. Take a production-safe (VSS-quiesced) checkpoint before patching and remove it afterward
Checkpoint-VM -Name "srv-sql-01" -SnapshotName "Pre-CU-2026-03"
Get-VMSnapshot -VMName "srv-sql-01"
Remove-VMSnapshot -VMName "srv-sql-01" -Name "Pre-CU-2026-03"

# 3. Export a live or stopped VM cleanly to backup storage
Export-VM -Name "deb-app-01" -Path "E:\Backups\VMs"

# 4. Compact a dynamic VHDX after deleting large files inside the guest (VM must be Off)
Stop-VM -Name "deb-app-01"
Mount-VHD -Path "D:\Hyper-V\Virtual Hard Disks\deb-app-01.vhdx" -ReadOnly
Optimize-VHD -Path "D:\Hyper-V\Virtual Hard Disks\deb-app-01.vhdx" -Mode Full
Dismount-VHD -Path "D:\Hyper-V\Virtual Hard Disks\deb-app-01.vhdx"
```

> **Watch out:** Running `Optimize-VHD -Mode Full` on a VHDX without first running `Mount-VHD -ReadOnly` skips NTFS free-block analysis and barely shrinks the file. Also never leave `Checkpoint-VM` snapshots on production database or Domain Controller VMs longer than a maintenance window—AVHDX differencing chains grow unchecked and degrade IOPS.

## Active Directory and RSAT Diagnostics

Query directory objects, inspect replication topology, and validate secure channels from Domain Controllers or management jump hosts.

### Install `[ROOT]`

```powershell
# Install AD PowerShell module, dcdiag, repadmin, and ADDS management tools
Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server
```

### ActiveDirectory PowerShell Module `[NON-ROOT]`

```powershell
# 1. Find enabled user accounts that have not logged in for 90+ days
$cutoff = (Get-Date).AddDays(-90)
Get-ADUser -Filter { Enabled -eq $true -and LastLogonDate -lt $cutoff } `
    -Properties LastLogonDate, PasswordLastSet, Department |
    Select-Object SamAccountName, LastLogonDate, PasswordLastSet, Department |
    Sort-Object LastLogonDate

# 2. List locked-out accounts and unlock a specific user
Search-ADAccount -LockedOut | Select-Object SamAccountName, LockedOut, LastLogonDate
Unlock-ADAccount -Identity "jdoe"

# 3. Inventory active Windows Server computer objects and OS versions
Get-ADComputer -Filter { OperatingSystem -like "*Server*" -and Enabled -eq $true } `
    -Properties OperatingSystem, OperatingSystemVersion, LastLogonDate |
    Select-Object Name, OperatingSystem, LastLogonDate |
    Sort-Object OperatingSystem
```

### dcdiag, repadmin, and nltest `[ROOT]`

```powershell
# 1. Run concise Domain Controller health checks (errors only) including DNS
dcdiag /q /test:DNS /test:Advertising /test:NetLogons /test:Replications /test:SysVolCheck

# 2. Summarize AD replication lag and failures across the entire forest
repadmin /replsummary
repadmin /showrepl * /errorsonly

# 3. Force immediate inbound replication on a DC and verify FSMO role holders
repadmin /syncall /AdeP
netdom query fsmo

# 4. Verify member server secure channel to its authenticating DC
nltest /sc_verify:corp.example.com
nltest /dsgetdc:corp.example.com /force
```

> **Watch out:** `LastLogonDate` is derived from `lastLogonTimestamp`, which only replicates when it is 9–14 days out of date. For exact logon timestamps during an incident, query the non-replicated `LastLogon` attribute across every DC in the domain rather than trusting a single DC's `LastLogonDate`.

## IIS Administration

Automate websites, TLS bindings, and application pools using the modern `IISAdministration` module (compatible with PowerShell 7) and `appcmd.exe`.

### Install `[ROOT]`

```powershell
# Install IIS Web Server role and CLI/PowerShell management tools
Install-WindowsFeature -Name Web-Server, Web-Mgmt-Tools, Web-Scripting-Tools
```

### Real-World Usages `[ROOT]`

```powershell
# 1. Inspect sites, physical paths, state, and HTTPS bindings with IISAdministration
Import-Module IISAdministration
Get-IISSite | Select-Object Name, Id, State, @{N='Bindings';E={$_.Bindings.BindingInformation -join ', '}}

# 2. Bind an existing certificate from LocalMachine\My to an IIS site on port 443 with SNI
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -like "*api.example.com*" | Select-Object -First 1
New-IISSiteBinding -Name "Default Web Site" `
    -BindingInformation "*:443:api.example.com" `
    -Protocol https `
    -CertificateThumbPrint $cert.Thumbprint `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -SslFlag Sni

# 3. Manage App Pools and trigger zero-downtime overlapped recycle via appcmd
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
& $appcmd list apppool
& $appcmd recycle apppool /apppool.name:"ApiPool"
& $appcmd list wp   # List active w3wp.exe worker processes with PID and AppPool name

# 4. Export full IIS site/apppool configuration before a migration
& $appcmd list site /config /xml > C:\Backup\iis-sites.xml
& $appcmd list apppool /config /xml > C:\Backup\iis-apppools.xml
```

> **Watch out:** `WebAdministration` relies on the legacy `IIS:\` PSDrive provider and fails or throws COM errors in PowerShell 7 unless wrapped in Windows PowerShell compatibility mode. Use `IISAdministration` (`Get-IISServerManager`) or `appcmd.exe` for deterministic behavior in `pwsh`. When modifying `Get-IISServerManager()` objects, changes are staged in memory until you explicitly call `$sm.CommitChanges()`.

## Storage Spaces and Disk Management

Provision resilient pools, virtual disks, and ReFS/NTFS volumes using the built-in `Storage` module.

### Install `[ROOT]`

Built into Windows Server 2019/2022/2025 (`Storage` module). No extra feature required for standalone Storage Spaces; for clustered Storage Spaces Direct (S2D), install `Failover-Clustering`.

### Real-World Usages `[ROOT]`

```powershell
# 1. Inspect raw physical disks eligible for pooling
Get-PhysicalDisk -CanPool $true | Format-Table FriendlyName, MediaType, BusType, Size, HealthStatus

# 2. Create a storage pool and a mirrored virtual disk formatted with ReFS (64K allocation for Hyper-V/Veeam)
$disks = Get-PhysicalDisk -CanPool $true
New-StoragePool -FriendlyName "Pool-Data01" `
    -StorageSubSystemFriendlyName "Windows Storage*" `
    -PhysicalDisks $disks

New-VirtualDisk -StoragePoolFriendlyName "Pool-Data01" `
    -FriendlyName "VD-HyperV" `
    -ResiliencySettingName Mirror `
    -ProvisioningType Thin `
    -Size 2TB |
    Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -AssignDriveLetter -UseMaximumSize |
    Format-Volume -FileSystem ReFS -AllocationUnitSize 65536 -NewFileSystemLabel "HyperV-Data" -Confirm:$false

# 3. Check pool and virtual disk health and trigger an explicit repair job after replacing a failed disk
Get-StoragePool | Format-Table FriendlyName, OperationalStatus, HealthStatus, Size, AllocatedSize
Get-VirtualDisk | Format-Table FriendlyName, ResiliencySettingName, OperationalStatus, HealthStatus
Repair-VirtualDisk -FriendlyName "VD-HyperV"
Get-StorageJob   # Monitor active rebuild/repair percentage
```

> **Watch out:** Thin-provisioned virtual disks on Storage Spaces do **not** automatically shrink pool allocation when files are deleted unless TRIM/UNMAP runs (`Optimize-Volume -DriveLetter D -ReTrim -Verbose`). If a thin pool hits 100% physical capacity, all virtual disks in the pool abruptly drop offline to `Detached` state until physical capacity is added.

## Modern Networking and Firewall

Replace `netstat`, `telnet`, and `netsh advfirewall` with structured object-returning cmdlets.

### Install `[ROOT]`

Built-in (`NetTCPIP`, `NetSecurity`, `DnsClient` modules).

### Real-World Usages `[ROOT]`

```powershell
# 1. Map every listening TCP port to its owning process and executable path
Get-NetTCPConnection -State Listen |
    Select-Object LocalAddress, LocalPort, OwningProcess,
        @{N='Process';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}},
        @{N='Path';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Path}} |
    Sort-Object LocalPort | Format-Table -AutoSize

# 2. Test TCP port reachability, routing interface, and hop trace (replaces telnet + tracert)
Test-NetConnection -ComputerName 10.20.10.50 -Port 1433 -InformationLevel Detailed
Test-NetConnection -ComputerName 8.8.8.8 -TraceRoute

# 3. Create a scoped inbound firewall rule allowing SQL only from app subnet
New-NetFirewallRule -DisplayName "SQL Server 1433 from App Tier" `
    -Name "App-SQL-1433-In" `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 1433 `
    -RemoteAddress 10.20.20.0/24 `
    -Profile Domain

# 4. Audit currently enabled inbound Allow rules
Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow |
    Get-NetFirewallPortFilter |
    Select-Object InstanceID, Protocol, LocalPort
```

> **Watch out:** `Test-NetConnection` performs an ICMP ping by default even when `-Port` is specified, which adds unnecessary latency if firewalls drop ICMP. Use `-Port` with awareness that `TcpTestSucceeded` is the authoritative boolean regardless of `PingSucceeded`.

## Event Logs with Get-WinEvent

`Get-WinEvent` queries modern ETW/EVTX channels (including `Microsoft-Windows-*` operational logs that legacy `Get-EventLog` cannot read) and filters server-side before returning objects.

### Install `[NON-ROOT]`

Built-in (`Microsoft.PowerShell.Diagnostics`). Reading the `Security` log requires `[ROOT]`.

### Real-World Usages `[ROOT]`

```powershell
# 1. Query failed logons (4625) in the last 24 hours with server-side FilterHashtable
Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4625
    StartTime = (Get-Date).AddHours(-24)
} -MaxEvents 50 | Select-Object TimeCreated,
    @{N='Account';E={$_.Properties[5].Value}},
    @{N='LogonType';E={$_.Properties[10].Value}},
    @{N='SourceIP';E={$_.Properties[19].Value}},
    @{N='FailureStatus';E={'0x{0:X}' -f $_.Properties[7].Value}}

# 2. Find unexpected reboots, bugchecks, and shutdowns over the last 7 days
Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Id        = 41, 1001, 1074, 6008
    StartTime = (Get-Date).AddDays(-7)
} | Select-Object TimeCreated, Id, ProviderName, Message | Format-Table -Wrap

# 3. Inspect OpenSSH Server authentication events
Get-WinEvent -FilterHashtable @{
    LogName   = 'OpenSSH/Operational'
    StartTime = (Get-Date).AddHours(-6)
} -MaxEvents 30 | Select-Object TimeCreated, Id, Message

# 4. Discover operational log names matching a subsystem
Get-WinEvent -ListLog "*Hyper-V*", "*SMB*", "*WinRM*" | Where-Object RecordCount -gt 0 |
    Format-Table LogName, RecordCount, MaximumSizeInBytes
```

> **Watch out:** Never pipe `Get-WinEvent -LogName Security | Where-Object Id -eq 4625` on a busy server—that deserializes millions of events client-side and exhausts RAM. Always filter using `-FilterHashtable` or `-FilterXPath` so the Event Log service filters inside the EVTX index.

## WinRM and Remote Sessions

Execute parallel commands across fleets of servers using persistent CIM and PowerShell remoting sessions.

### Install `[ROOT]`

Built-in (`WSMan` provider and `CimCmdlets`).

### Real-World Usages `[ROOT]`

```powershell
# 1. Run a read-only check across multiple servers concurrently (default throttle = 32)
$servers = "srv-app-01", "srv-app-02", "srv-db-01"
Invoke-Command -ComputerName $servers -ScriptBlock {
    [PSCustomObject]@{
        Host       = $env:COMPUTERNAME
        FreeC_GB   = [math]::Round((Get-Volume -DriveLetter C).SizeRemaining / 1GB, 2)
        PendingRbt = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    }
}

# 2. Copy a file directly over WinRM without needing SMB (port 445) open
$session = New-PSSession -ComputerName "srv-app-01" -UseSSL
Copy-Item -Path "C:\Deploy\app.zip" -Destination "C:\Temp\app.zip" -ToSession $session
Remove-PSSession $session

# 3. Inspect and tune WinRM shell memory and concurrent connection limits
Get-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB
Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB 2048
Get-Item WSMan:\localhost\Service\MaxConcurrentOperationsPerUser
```

> **Watch out:** Using `Invoke-Command` to access a network share or remote database from inside a remote session fails with `Access Denied` due to Kerberos double-hop restrictions. Do not enable CredSSP broadly to work around it; instead use Kerberos Resource-Based Constrained Delegation (RBCD), JEA endpoints, or pass credentials strictly when required.
