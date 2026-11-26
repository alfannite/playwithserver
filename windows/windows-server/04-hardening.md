# Windows Server Security Hardening

Production-safe security baseline for Windows Server 2019, 2022, and 2025: OpenSSH hardening, SMBv1 removal and SMB signing, WinRM encryption, TLS cipher hygiene, Windows Defender configuration, PowerShell logging, and Firewall baselines that preserve AD, Hyper-V, IIS, and container workloads.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Hardening Principles and Blast-Radius Guardrails](#hardening-principles-and-blast-radius-guardrails)
- [OpenSSH Server Hardening](#openssh-server-hardening)
- [WinRM and RDP Access Controls](#winrm-and-rdp-access-controls)
- [SMB Protocol Hardening](#smb-protocol-hardening)
- [TLS and Schannel Baseline](#tls-and-schannel-baseline)
- [Windows Firewall and Network Isolation](#windows-firewall-and-network-isolation)
- [PowerShell Script Block Logging and Auditing](#powershell-script-block-logging-and-auditing)
- [Defender, Credential Guard, and Local Account Hygiene](#defender-credential-guard-and-local-account-hygiene)

## Hardening Principles and Blast-Radius Guardrails

| Control | Safe Production Setting | What Breaks If Over-Hardened |
| --- | --- | --- |
| Windows Firewall | Enabled on Domain/Private/Public, explicit Allow rules | Blocking ICMPv4 Type 3/4 breaks PMTUD; blocking RPC ephemeral (49152–65535) breaks AD/WMI |
| SMB Signing | Required on Server & Client | Legacy NAS/MFPs supporting only SMBv1 or unsigned SMBv2 fail |
| TLS | TLS 1.2 + TLS 1.3 only | Disabling TLS 1.2 breaks older .NET 4.x apps and SQL drivers that lack TLS 1.3 |
| NTLM | Restrict NTLMv1 (`LmCompatibilityLevel = 5`); audit NTLMv2 before blocking | Blindly denying NTLMv2 breaks local accounts, IP-based SMB/RDP, and non-Kerberos apps |
| PowerShell | Constrained Language Mode only via AppLocker/WDAC where tested; always enable Script Block Logging | Setting `ExecutionPolicy Restricted` breaks administrative automation without stopping attackers |

## OpenSSH Server Hardening

Harden `C:\ProgramData\ssh\sshd_config` **only after** testing key-based logon in a separate active session.

`[ROOT]`
```powershell
# Back up existing configuration
Copy-Item "C:\ProgramData\ssh\sshd_config" "C:\ProgramData\ssh\sshd_config.bak"

# Verify authorized_keys file exists and has strict NTFS ACLs before disabling passwords
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys"
```

Apply these hardened directives inside `C:\ProgramData\ssh\sshd_config`:

```text
Port 22
AddressFamily inet
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
AllowTcpForwarding local
X11Forwarding no
AllowGroups Administrators ssh-users

Match Group administrators
    AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

Validate syntax and restart `sshd` while keeping your current session open:

`[ROOT]`
```powershell
# Validate sshd_config syntax before restarting service
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -t

# Restart sshd only if validation exits with code 0
if ($LASTEXITCODE -eq 0) { Restart-Service sshd }
```

> **Watch out:** `AllowGroups` on Windows OpenSSH matches local group names in **lowercase** on many Win32-OpenSSH builds (`administrators` instead of `Administrators`), and domain groups require `domain\groupname` in lowercase. Always test a brand-new SSH login in a second terminal before closing your existing session.

## WinRM and RDP Access Controls

### Enforce Encrypted WinRM and Disable Basic Auth `[ROOT]`

```powershell
# Disable unencrypted traffic and Basic authentication on WinRM service and client
Set-Item WSMan:\localhost\Service\AllowUnencrypted $false
Set-Item WSMan:\localhost\Service\Auth\Basic $false
Set-Item WSMan:\localhost\Client\AllowUnencrypted $false
Set-Item WSMan:\localhost\Client\Auth\Basic $false

# Once HTTPS listener (5986) is verified working, remove the HTTP listener (5985) if not needed by legacy tooling
# Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTP" } | Remove-Item -Recurse
```

### Enforce Network Level Authentication (NLA) for RDP `[ROOT]`

```powershell
# Require NLA and TLS security layer for RDP (only when RDP is enabled)
$rdpKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
Set-ItemProperty -Path $rdpKey -Name "UserAuthentication" -Value 1 -Type DWord
Set-ItemProperty -Path $rdpKey -Name "SecurityLayer" -Value 2 -Type DWord
Set-ItemProperty -Path $rdpKey -Name "MinEncryptionLevel" -Value 3 -Type DWord

# Restrict RDP inbound firewall rule to jump-host subnet
Set-NetFirewallRule -DisplayGroup "Remote Desktop" -RemoteAddress "10.20.10.0/24"
```

## SMB Protocol Hardening

Eliminate SMBv1, require SMB signing to stop NTLM relay attacks, and enable SMB encryption on sensitive shares.

`[ROOT]` `[REBOOT]`
```powershell
# Disable SMBv1 server protocol and remove the optional feature entirely
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart

# Require SMB signing on both server and client
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
Set-SmbClientConfiguration -RequireSecuritySignature $true -Force

# Disable anonymous/guest fallback on SMB client
Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force

# Optional: enable SMB encryption globally (Windows Server 2012+ / SMB 3.x clients only)
# Set-SmbServerConfiguration -EncryptData $true -RejectUnencryptedAccess $true -Force

# Verify active SMB server configuration
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol, RequireSecuritySignature, EncryptData
```

## TLS and Schannel Baseline

Disable SSL 2.0, SSL 3.0, TLS 1.0, and TLS 1.1 while keeping TLS 1.2 (and TLS 1.3 on Server 2022/2025) enabled.

`[ROOT]` `[REBOOT]`
```powershell
$protocols = @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")
foreach ($proto in $protocols) {
    foreach ($side in @("Server", "Client")) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\$side"
        New-Item -Path $path -Force | Out-Null
        New-ItemProperty -Path $path -Name "Enabled" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $path -Name "DisabledByDefault" -Value 1 -PropertyType DWord -Force | Out-Null
    }
}

# Explicitly ensure TLS 1.2 is enabled
foreach ($side in @("Server", "Client")) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\$side"
    New-Item -Path $path -Force | Out-Null
    New-ItemProperty -Path $path -Name "Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name "DisabledByDefault" -Value 0 -PropertyType DWord -Force | Out-Null
}

# Force .NET Framework 4.x apps to use OS strong crypto defaults
foreach ($arch in @("HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319")) {
    if (Test-Path $arch) {
        Set-ItemProperty -Path $arch -Name "SchUseStrongCrypto" -Value 1 -Type DWord
        Set-ItemProperty -Path $arch -Name "SystemDefaultTlsVersions" -Value 1 -Type DWord
    }
}
```

> **Watch out:** Disabling TLS 1.0/1.1 without setting `SchUseStrongCrypto` and `SystemDefaultTlsVersions` on .NET 4.x causes legacy PowerShell modules, SQL Server Management Studio, and IIS .NET 4.5–4.7 apps to fail outbound HTTPS handshakes. Reboot after modifying Schannel registry keys so `lsass.exe` reloads cipher suites.

## Windows Firewall and Network Isolation

Keep Windows Firewall active on all three profiles with default-deny inbound and explicit Allow rules.

`[ROOT]`
```powershell
# Enable all firewall profiles with default-deny inbound and allow outbound
Set-NetFirewallProfile -Profile Domain,Private,Public `
    -Enabled True `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Allow `
    -LogBlocked True `
    -LogFileName "%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log" `
    -LogMaxSizeKilobytes 16384

# Disable LLMNR and NetBIOS over TCP/IP to mitigate responder/poisoning attacks
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" `
    -Name "EnableMulticast" -Value 0 -PropertyType DWord -Force

# Disable NetBIOS (NetbiosOptions = 2) on all active adapters
Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" |
    Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 }
```

## PowerShell Script Block Logging and Auditing

Record full de-obfuscated PowerShell execution and process creation command lines for incident response without breaking scripts.

`[ROOT]`
```powershell
# Enable PowerShell Script Block Logging (Event ID 4104)
$sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
New-Item -Path $sbPath -Force | Out-Null
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord

# Enable Module Logging (Event ID 4103)
$modPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
New-Item -Path "$modPath\ModuleNames" -Force | Out-Null
Set-ItemProperty -Path $modPath -Name "EnableModuleLogging" -Value 1 -Type DWord
Set-ItemProperty -Path "$modPath\ModuleNames" -Name "*" -Value "*" -Type String

# Include full command line in Process Creation events (Event ID 4688)
$auditKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
New-Item -Path $auditKey -Force | Out-Null
Set-ItemProperty -Path $auditKey -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord

# Enable Advanced Audit Policy for Process Creation and Logon failures
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
```

## Defender, Credential Guard, and Local Account Hygiene

### Windows Defender Server Baseline `[ROOT]`

```powershell
# Ensure real-time monitoring, cloud protection, and PUA protection are enabled
Set-MpPreference -DisableRealtimeMonitoring $false `
    -MAPSReporting Advanced `
    -PUAProtection Enabled

# Add required Hyper-V exclusions on virtualization hosts to avoid VM I/O stalls
# Add-MpPreference -ExclusionPath "D:\Hyper-V\Virtual Hard Disks", "D:\Hyper-V\Virtual Machines"
# Add-MpPreference -ExclusionProcess "vmms.exe", "vmwp.exe"
```

### NTLMv1 Removal and LSA Protection `[ROOT]` `[REBOOT]`

```powershell
# Refuse LM and NTLMv1; send NTLMv2 response only (Level 5)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "LmCompatibilityLevel" -Value 5 -Type DWord

# Enable LSA Protection (RunAsPPL) to block user-mode credential dumping from lsass.exe
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "RunAsPPL" -Value 1 -Type DWord

# Verify Defender and Credential Guard status
Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard |
    Select-Object SecurityServicesConfigured, SecurityServicesRunning
```

> **Watch out:** Before enabling `RunAsPPL = 1` on domain controllers or servers running third-party password filters or legacy EDR agents, verify those DLLs are Microsoft-signed for PPL. Unsigned LSA plugins fail to load when `RunAsPPL` is enabled (logged as Event ID 3033 in `Microsoft-Windows-CodeIntegrity/Operational`).
