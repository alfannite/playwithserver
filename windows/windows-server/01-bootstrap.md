# Windows Server Bootstrap

First-boot provisioning for Windows Server 2019, 2022, and 2025 (Server Core and Desktop Experience): host identity, static networking, `sconfig`, OpenSSH Server with hardened key authentication, WinRM over HTTPS, PowerShell 7, time synchronization, and virtualization guest tools.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Server Core Initial Setup with sconfig](#server-core-initial-setup-with-sconfig)
- [Hostname, Static Networking, and DNS](#hostname-static-networking-and-dns)
- [Windows Update and PowerShell 7](#windows-update-and-powershell-7)
- [OpenSSH Server and Key-Based Authentication](#openssh-server-and-key-based-authentication)
- [WinRM and PowerShell Remoting](#winrm-and-powershell-remoting)
- [Time Synchronization with w32tm](#time-synchronization-with-w32tm)
- [Hyper-V Role and Guest Integration Services](#hyper-v-role-and-guest-integration-services)
- [Post-Bootstrap Verification](#post-bootstrap-verification)

## Server Core Initial Setup with sconfig

Windows Server 2022 and 2025 Server Core launch `sconfig` automatically on interactive console logon. On Server 2019 or Desktop Experience, invoke it from an elevated PowerShell prompt.

`[ROOT]`
```powershell
# Launch the Server Configuration TUI
sconfig

# Disable automatic launch of sconfig on Server Core logon (opens pwsh/powershell directly)
Set-SConfig -AutoLaunch $false
```

| `sconfig` Option | Function | PowerShell Equivalent |
| --- | --- | --- |
| `1` | Join Domain / Workgroup | `Add-Computer -DomainName corp.example.com -Restart` |
| `2` | Change Computer Name | `Rename-Computer -NewName "SRV-APP-01" -Restart` |
| `5` | Windows Update Settings | `Set-SConfig` / `PSWindowsUpdate` |
| `6` | Download and Install Updates | `Install-WindowsUpdate` |
| `7` | Enable Remote Desktop | `Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0` |
| `8` | Network Settings | `New-NetIPAddress`, `Set-DnsClientServerAddress` |
| `15` | Exit to Command Line (PowerShell) | Opens interactive shell |

> **Watch out:** On Server Core 2022/2025, `sconfig` runs inside a PowerShell session (`pwsh` or `powershell.exe`). Typing `15` drops to PowerShell; typing `sconfig` returns to the menu. Closing the console window leaves a blank desktop—press `Ctrl+Shift+Esc` -> **File -> Run new task** -> `powershell.exe` to recover without rebooting.

## Hostname, Static Networking, and DNS

Configure deterministic interface addressing before joining a domain or enabling management endpoints.

`[ROOT]` `[REBOOT]`
```powershell
# Inspect physical adapters and current interface index
Get-NetAdapter | Format-Table Name, InterfaceDescription, ifIndex, Status, LinkSpeed

# Disable DHCP and assign static IPv4 address + gateway
$ifIndex = (Get-NetAdapter -Name "Ethernet0").ifIndex
Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled
New-NetIPAddress -InterfaceIndex $ifIndex `
    -IPAddress 10.20.10.15 `
    -PrefixLength 24 `
    -DefaultGateway 10.20.10.1

# Configure DNS servers and connection-specific suffix
Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses ("10.20.10.5", "10.20.10.6")
Set-DnsClient -InterfaceIndex $ifIndex -ConnectionSpecificSuffix "corp.example.com"

# Disable IPv6 Privacy Extensions on servers so static/SLAAC addresses remain predictable
Set-NetIPv6Protocol -UseTemporaryAddresses Disabled

# Rename server (requires reboot)
Rename-Computer -NewName "SRV-APP-01" -Restart
```

> **Watch out:** Running `New-NetIPAddress` on an interface that already holds a static IPv4 address throws a `DefaultGateway already exists` error or leaves stale secondary IPs attached. Clear old addresses first with `Remove-NetIPAddress -InterfaceIndex $ifIndex -Confirm:$false` and `Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false` when re-addressing over console (never remotely without a rollback timer).

## Windows Update and PowerShell 7

Install PowerShell 7 (`pwsh`) and the `PSWindowsUpdate` module so patching and automation run identically across Server Core and Desktop Experience.

`[ROOT]`
```powershell
# Ensure TLS 1.2 is enabled for PowerShell Gallery on Server 2019
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Bootstrap NuGet provider and trust PSGallery
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install PSWindowsUpdate for scripted patching
Install-Module -Name PSWindowsUpdate -Force

# Install latest PowerShell 7 MSI silently (Server Core friendly)
$pwshRelease = Invoke-RestMethod "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
$msiUrl = ($pwshRelease.assets | Where-Object Name -like "*win-x64.msi").browser_download_url
Invoke-WebRequest -Uri $msiUrl -OutFile "$env:TEMP\pwsh.msi"
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$env:TEMP\pwsh.msi`" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1"

# Verify pwsh installation
& "$env:ProgramFiles\PowerShell\7\pwsh.exe" -NoProfile -Command '$PSVersionTable.PSVersion'
```

Patch immediately after initial provisioning:

`[ROOT]` `[REBOOT]`
```powershell
# List and install available Windows Updates, rebooting automatically if required
Get-WindowsUpdate -MicrosoftUpdate
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
```

## OpenSSH Server and Key-Based Authentication

Windows Server 2019+ ships OpenSSH Server as a Feature on Demand (FoD). Server 2025 includes OpenSSH pre-staged; earlier builds install via `Add-WindowsCapability`.

### Install and Enable sshd `[ROOT]`

```powershell
# Check exact capability name and install OpenSSH Server
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start service and configure automatic startup
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Verify firewall rule exists (created automatically on most builds)
if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
        -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22
}
```

### Set PowerShell 7 as the Default SSH Shell `[ROOT]`

```powershell
# Point OpenSSH default shell to PowerShell 7 (use powershell.exe if pwsh is not installed)
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" `
    -Name DefaultShell `
    -Value "C:\Program Files\PowerShell\7\pwsh.exe" `
    -PropertyType String `
    -Force

# Optional: skip logo banner on SSH logon
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" `
    -Name DefaultShellCommandOption `
    -Value "-NoLogo -c" `
    -PropertyType String `
    -Force
```

### Configure Administrator Authorized Keys and NTFS ACLs `[ROOT]`

By default, `C:\ProgramData\ssh\sshd_config` contains a `Match Group administrators` block that **ignores** `%USERPROFILE%\.ssh\authorized_keys` for any user in the local `Administrators` group and reads `C:\ProgramData\ssh\administrators_authorized_keys` instead.

```powershell
# Deploy admin public key
$authKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
Set-Content -Path $authKeys -Value "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyData admin@workstation" -Encoding ascii

# Strip inherited permissions and grant access ONLY to Administrators and SYSTEM
icacls.exe $authKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

# Verify exact ACLs (no Users, Authenticated Users, or individual accounts allowed)
icacls.exe $authKeys

# Restart sshd to apply changes
Restart-Service sshd
```

> **Watch out:** If `C:\ProgramData\ssh\administrators_authorized_keys` retains inherited NTFS permissions (e.g., `BUILTIN\Users:(R)` or `NT AUTHORITY\Authenticated Users`), `sshd` silently rejects public-key auth and falls back to password prompts without obvious client-side errors. Always verify with `icacls.exe` and confirm only `BUILTIN\Administrators:(F)` and `NT AUTHORITY\SYSTEM:(F)` appear. Also ensure the file is ASCII/UTF-8 **without BOM** (`Set-Content -Encoding ascii` in Windows PowerShell 5.1, since `-Encoding utf8` in 5.1 writes a UTF-8 BOM that breaks the first key line).

## WinRM and PowerShell Remoting

Enable PowerShell Remoting and bind an HTTPS listener so management traffic does not rely solely on HTTP port 5985.

`[ROOT]`
```powershell
# Enable PSRemoting (starts WinRM, sets Automatic startup, creates HTTP listener + firewall rule)
Enable-PSRemoting -Force

# Verify current WinRM listeners
Get-ChildItem WSMan:\localhost\Listener

# Create a self-signed certificate for HTTPS WinRM (or use your internal PKI cert thumbprint)
$fqdn = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME)).HostName
$cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My

# Create WinRM HTTPS listener on TCP 5986
New-Item -Path WSMan:\localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $cert.Thumbprint `
    -HostName $fqdn `
    -Force

# Open TCP 5986 in Windows Firewall restricted to management subnet
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" `
    -Name "WINRM-HTTPS-In-TCP" `
    -Profile Domain,Private `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 5986 `
    -RemoteAddress 10.20.10.0/24

# Register PowerShell 7 remoting endpoint (allows Enter-PSSession -ConfigurationName PowerShell.7)
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -Command "Enable-PSRemoting -Force"
```

Test remote connectivity from an admin workstation:

`[NON-ROOT]`
```powershell
$so = New-PSSessionOption -SkipCACheck -SkipCNCheck
Enter-PSSession -ComputerName srv-app-01.corp.example.com -UseSSL -SessionOption $so -ConfigurationName PowerShell.7
```

## Time Synchronization with w32tm

Accurate time is mandatory for Kerberos (5-minute max skew), TLS certificates, and clustered logs.

### Domain-Joined Member Server `[ROOT]`

```powershell
# Sync automatically from domain hierarchy (NT5DS)
w32tm /config /syncfromflags:domhier /update
Restart-Service w32time
w32tm /resync /rediscover
```

### Standalone Server or PDC Emulator `[ROOT]`

```powershell
# Configure external NTP peers (0x8 = client mode; 0x9 = client + SpecialPollInterval)
w32tm /config /manualpeerlist:"time.cloudflare.com,0x8 pool.ntp.org,0x8" /syncfromflags:manual /reliable:YES /update
Set-Service -Name w32time -StartupType Automatic
Restart-Service w32time
w32tm /resync /force

# Verify active source, stratum, and offset
w32tm /query /status
w32tm /query /peers
```

## Hyper-V Role and Guest Integration Services

### Bare-Metal Host: Install Hyper-V Role `[ROOT]` `[REBOOT]`

```powershell
# Install Hyper-V role + PowerShell management module (and GUI tools on Desktop Experience)
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

After reboot, create an external virtual switch with management OS sharing enabled:

`[ROOT]`
```powershell
# Create an External vSwitch on physical NIC "Ethernet0"
New-VMSwitch -Name "vSwitch-External" -NetAdapterName "Ethernet0" -AllowManagementOS $true

# Set default VM and VHD storage paths away from C:
Set-VMHost -VirtualHardDiskPath "D:\Hyper-V\Virtual Hard Disks" `
    -VirtualMachinePath "D:\Hyper-V\Virtual Machines"
```

### Virtualized Guest: Verify Integration Services / Guest Agents `[ROOT]`

```powershell
# On Hyper-V guests: verify all integration services are running
Get-Service vmicheartbeat, vmickvpexchange, vmicrdv, vmicshutdown, vmictimesync, vmicvss |
    Format-Table Name, Status, StartType

# On KVM/Proxmox guests: verify QEMU Guest Agent and VirtIO Balloon service
Get-Service QEMU-GA, BalloonService -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType
```

> **Watch out:** On domain-joined Windows Server VMs running on Hyper-V, disable Hyper-V Time Synchronization integration service for Domain Controllers (or set `VMICTimeProvider` to disabled) so the hypervisor clock does not fight Active Directory `NT5DS` time hierarchy.

## Post-Bootstrap Verification

Run this validation checklist after rebooting and before handing the server over to application teams.

`[ROOT]`
```powershell
# 1. Confirm OS version, uptime, and domain membership
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime
(Get-CimInstance Win32_ComputerSystem).Domain

# 2. Confirm static IP and DNS resolution
Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -notlike "*Loopback*" |
    Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin
Resolve-DnsName corp.example.com

# 3. Confirm SSH (22) and WinRM HTTPS (5986) are listening
Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 22, 5985, 5986, 3389 |
    Select-Object LocalAddress, LocalPort, OwningProcess, @{N='Process';E={(Get-Process -Id $_.OwningProcess).Name}}

# 4. Confirm NTP sync health
w32tm /query /source
w32tm /query /status | Select-String "Source|Stratum|Last Successful Sync Time"

# 5. Confirm critical services are running
Get-Service sshd, WinRM, w32time, EventLog | Format-Table Name, Status, StartType
```
