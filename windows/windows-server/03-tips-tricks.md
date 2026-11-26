# Windows Server Tips and Tricks

High-signal operational patterns for Windows Server 2019, 2022, and 2025: Server Core productivity, Hyper-V live maintenance, IIS zero-downtime workflows, Event Log XML extraction, storage tuning, and fast remote diagnostics.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Server Core Survival and Shell Productivity](#server-core-survival-and-shell-productivity)
- [OpenSSH and WinRM Dual-Transport Workflows](#openssh-and-winrm-dual-transport-workflows)
- [Hyper-V Performance and Live Operations](#hyper-v-performance-and-live-operations)
- [IIS and Certificate Rotation Without Downtime](#iis-and-certificate-rotation-without-downtime)
- [Event Log XPath and Subscription Tricks](#event-log-xpath-and-subscription-tricks)
- [Storage, ReFS, and NTFS Tuning](#storage-refs-and-ntfs-tuning)

## Server Core Survival and Shell Productivity

### Recover a Closed Console Session on Server Core `[ROOT]`

If you accidentally close the only `cmd.exe`/`pwsh.exe` window on a Server Core console and are staring at a blank background:
1. Press `Ctrl+Shift+Esc` (or send `Ctrl+Alt+Del` in Hyper-V/iDRAC/iLO -> **Task Manager**).
2. Click **File -> Run new task** -> enter `pwsh` (or `powershell.exe`) with **Create this task with administrative privileges** checked.

### Launch Built-in Mini-Tools on Server Core `[ROOT]`

Server Core lacks Explorer and MMC, but several lightweight diagnostic GUIs still ship locally:

| Command | Utility | Purpose |
| --- | --- | --- |
| `taskmgr` | Task Manager | Quick CPU/RAM/disk inspection and launching new shells |
| `regedit` | Registry Editor | Fast interactive registry browsing on console |
| `notepad` | Notepad | Quick edits to `sshd_config`, `hosts`, or `applicationHost.config` |
| `msinfo32` | System Information | Hardware, driver, and BIOS summary |
| `intl.cpl` / `timedate.cpl` | Regional / Time Applets | Time zone and locale fixes |

### Add Server Core App Compatibility Feature on Demand `[ROOT]` `[REBOOT]`

When a legacy enterprise installer or MMC snap-in (`diskmgmt.msc`, `perfmon.msc`, `eventvwr.msc`) refuses to run on Server Core, install the App Compatibility FoD rather than rebuilding with Desktop Experience:

```powershell
Add-WindowsCapability -Online -Name ServerCore.AppCompatibility~~~~0.0.1.0
Restart-Computer
```

## OpenSSH and WinRM Dual-Transport Workflows

### PowerShell 7 Remoting Over SSH (No WinRM Required) `[NON-ROOT]`

PowerShell 7 natively supports SSH as a remoting transport, letting you manage Linux and Windows servers with identical `Invoke-Command` / `Enter-PSSession` workflows over port 22.

Add this subsystem line to `C:\ProgramData\ssh\sshd_config` on the Windows Server target (`[ROOT]`):

```text
Subsystem powershell C:/PROGRA~1/PowerShell/7/pwsh.exe -sshs -NoLogo -NoProfile
```

> **Watch out:** OpenSSH on Windows chokes on spaces inside `Subsystem` paths (`C:\Program Files\...`). Always use the 8.3 short path (`C:/PROGRA~1/PowerShell/7/pwsh.exe`), verify it exists with `cmd /c for %I in ("C:\Program Files\PowerShell\7\pwsh.exe") do @echo %~sI`, and restart `sshd`.

Then connect from any Linux, macOS, or Windows workstation running PowerShell 7:

`[NON-ROOT]`
```powershell
Enter-PSSession -HostName srv-app-01.corp.example.com -UserName administrator -KeyFilePath ~/.ssh/id_ed25519
```

### ProxyJump Through a Windows Bastion Over SSH `[NON-ROOT]`

Use standard `~/.ssh/config` on your workstation to jump through a Windows Server OpenSSH bastion without exposing internal servers:

```sshconfig
Host bastion-win
    HostName 203.0.113.10
    User opsadmin
    IdentityFile ~/.ssh/id_ed25519

Host srv-internal-01
    HostName 10.20.10.25
    User opsadmin
    ProxyJump bastion-win
    IdentityFile ~/.ssh/id_ed25519
```

## Hyper-V Performance and Live Operations

### Disable Dynamic Memory for Latency-Sensitive Workloads `[ROOT]`

Dynamic Memory causes NUMA spanning and ballooning stalls on SQL Server, Exchange, and Kubernetes nodes. Assign static RAM and lock NUMA alignment:

```powershell
Set-VMMemory -VMName "srv-sql-01" -DynamicMemoryEnabled $false -StartupBytes 32GB
Get-VMHostNumaNode | Format-Table NodeId, ProcessorsAvailability, MemoryAvailable, MemoryTotal
```

### Enable Nested Virtualization for Lab/Container Hosts `[ROOT]`

Run Hyper-V, WSL2, or KVM inside a Windows Server Hyper-V VM (VM must be Off):

```powershell
Set-VMProcessor -VMName "lab-host-01" -ExposeVirtualizationExtensions $true
# Allow MAC spoofing on the VM NIC so nested VMs can route out
Get-VMNetworkAdapter -VMName "lab-host-01" | Set-VMNetworkAdapter -MacAddressSpoofing On
```

### Live-Resize a Generation 2 VHDX Without Rebooting `[ROOT]`

Generation 2 VMs attach disks to a virtual SCSI controller, allowing online expansion:

```powershell
# On Hyper-V host: expand VHDX from 60GB to 120GB while VM is running
Resize-VHD -Path "D:\Hyper-V\Virtual Hard Disks\srv-app-01.vhdx" -SizeBytes 120GB

# Inside Windows guest: extend partition to consume unallocated space
Update-HostStorageCache
$max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
Resize-Partition -DriveLetter C -Size $max
```

### Direct VM Management Without Networking via PowerShell Direct `[ROOT]`

When a VM's NIC is misconfigured or firewall rules lock you out, connect over the Hyper-V VMBus directly from the host:

```powershell
Enter-PSSession -VMName "srv-app-01" -Credential (Get-Credential)
# Copy a recovery script over VMBus
$s = New-PSSession -VMName "srv-app-01" -Credential (Get-Credential)
Copy-Item -Path "C:\Scripts\fix-nic.ps1" -Destination "C:\Temp\fix-nic.ps1" -ToSession $s
```

## IIS and Certificate Rotation Without Downtime

### Rebind a Renewed Certificate Across All Matching Sites `[ROOT]`

Avoid manual IIS Manager clicking when rotating wildcard or SAN certificates:

`[ROOT]`
```powershell
Import-Module IISAdministration
$newThumb = (Get-ChildItem Cert:\LocalMachine\My |
    Where-Object Subject -like "*example.com*" |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1).Thumbprint

$sm = Get-IISServerManager
foreach ($site in $sm.Sites) {
    foreach ($binding in $site.Bindings | Where-Object { $_.Protocol -eq 'https' -and $_.Host -like '*example.com' }) {
        $binding.CertificateHash = [byte[]]::new(20)
        for ($i = 0; $i -lt 20; $i++) {
            $binding.CertificateHash[$i] = [Convert]::ToByte($newThumb.Substring($i * 2, 2), 16)
        }
        $binding.CertificateStoreName = "My"
        Write-Host "Updated binding $($binding.BindingInformation) on site $($site.Name)"
    }
}
$sm.CommitChanges()
```

### Pin Worker Process Inspection for High-CPU Troubleshooting `[ROOT]`

Map a spiking `w3wp.exe` PID to its exact IIS Application Pool and currently executing HTTP requests:

```powershell
# Identify which AppPool owns each w3wp.exe PID
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list wp

# List currently in-flight HTTP requests taking > 2 seconds
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" list request /elapsed:2000
```

## Event Log XPath and Subscription Tricks

### Extract Named EventData Fields Cleanly via XML `[ROOT]`

Positional `$_.Properties[N].Value` indices shift between Windows builds. Convert event XML for readable, schema-stable field extraction:

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624; StartTime = (Get-Date).AddHours(-1) } -MaxEvents 20 |
    ForEach-Object {
        $xml = [xml]$_.ToXml()
        $data = @{}
        foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.'#text' }
        [PSCustomObject]@{
            Time       = $_.TimeCreated
            User       = $data['TargetUserName']
            LogonType  = $data['LogonType']
            SourceIP   = $data['IpAddress']
            AuthPkg    = $data['AuthenticationPackageName']
        }
    } | Format-Table -AutoSize
```

### Increase Security and Operational Log Retention `[ROOT]`

Default Windows Server EVTX sizes (20 MB) wrap within hours on Domain Controllers and busy file servers. Expand retention immediately:

```powershell
# Expand Security log to 1 GB and System/Application to 256 MB
wevtutil sl Security /ms:1073741824
wevtutil sl System /ms:268435456
wevtutil sl Application /ms:268435456
wevtutil sl "Microsoft-Windows-PowerShell/Operational" /ms:268435456
```

## Storage, ReFS, and NTFS Tuning

### Disable 8.3 Short Names and Last-Access Updates on High-IOPS Data Volumes `[ROOT]`

NTFS 8.3 filename generation degrades directory creation performance exponentially once a folder holds >100,000 files.

```powershell
# Check current behavior (0 = enabled all, 1 = disabled all, 2 = per-volume)
fsutil 8dot3name query D:

# Disable 8.3 name creation on data volume D: (keep enabled on C: for Program Files compatibility)
fsutil 8dot3name set D: 1

# Verify NTFS last-access timestamp updates are disabled (system managed or user disabled)
fsutil behavior query disablelastaccess
```

> **Watch out:** Never disable 8.3 short names globally (`fsutil 8dot3name set 1`) on `C:` if you use OpenSSH `Subsystem` paths (`PROGRA~1`) or older MSI installers that rely on 8.3 paths. Apply per-volume tuning strictly to dedicated data drives.

### Enable PowerShell High-Performance Power Plan on Bare-Metal Hosts `[ROOT]`

Windows Server defaults to the **Balanced** power plan, which parks CPU cores and throttles clock frequencies on virtualization hosts and database servers, adding measurable tail latency.

```powershell
# Inspect active power scheme
powercfg /getactivescheme

# Switch to High Performance
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```
