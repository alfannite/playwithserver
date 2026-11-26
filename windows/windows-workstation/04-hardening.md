# Windows Workstation Security Hardening

Practical security baseline for Windows 10/11 Pro and Enterprise engineering workstations: BitLocker full-disk encryption, Defender Attack Surface Reduction (ASR) and Controlled Folder Access tuning, Credential Guard/HVCI, Windows Firewall hygiene, PowerShell logging, and browser/account protections that keep Docker Desktop, WSL2, Hyper-V, and SSH workflows intact.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Hardening Guardrails for Developer Workstations](#hardening-guardrails-for-developer-workstations)
- [BitLocker Full-Disk Encryption](#bitlocker-full-disk-encryption)
- [Windows Defender, ASR Rules, and PUA Protection](#windows-defender-asr-rules-and-pua-protection)
- [Core Isolation, HVCI, and LSA Protection](#core-isolation-hvci-and-lsa-protection)
- [Network, Firewall, and Protocol Hardening](#network-firewall-and-protocol-hardening)
- [Local Account, UAC, and Execution Hygiene](#local-account-uac-and-execution-hygiene)
- [Hardening Verification Checklist](#hardening-verification-checklist)

## Hardening Guardrails for Developer Workstations

| Control | Recommended Setting | What Breaks If Misconfigured |
| --- | --- | --- |
| BitLocker | XTS-AES-256 with TPM + Recovery Key escrowed | Enabling BitLocker without backing up recovery key risks permanent data loss after BIOS/TPM updates |
| Defender ASR Rules | Start in `AuditMode` (`2`), promote high-confidence rules to `Enabled` (`1`) | Blocking unsigned PS/JS scripts globally can break local build tools (`npm`, `pip`, `pwsh` scripts) |
| HVCI (Memory Integrity) | Enabled on modern Win11 hardware | Very old unsigned USB-to-serial or VPN kernel drivers refuse to load |
| Windows Firewall | Enabled on all profiles; Inbound Block default | Blocking Hyper-V/WSL2 virtual switch traffic breaks container host-to-guest networking |
| UAC | Always Notify or Default (prompt on secure desktop) | Setting UAC to "Never Notify" silently grants elevation to any process |

## BitLocker Full-Disk Encryption

Encrypt OS and secondary data drives with XTS-AES-256 and store the recovery password off-device (password manager or Entra ID / AD escrow) before enforcing encryption.

`[ROOT]` `[REBOOT]`
```powershell
# 1. Verify TPM 2.0 readiness
Get-Tpm | Select-Object TpmPresent, TpmReady, TpmEnabled, TpmActivated

# 2. Enforce XTS-AES-256 encryption method via policy before enabling BitLocker
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\FVE" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\FVE" -Name "EncryptionMethodWithXtsOs" -Value 7 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\FVE" -Name "EncryptionMethodWithXtsFdv" -Value 7 -Type DWord

# 3. Enable BitLocker on C: (UsedSpaceOnly for fresh install; omit for existing drives with sensitive prior data)
Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector -SkipHardwareTest
Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector

# 4. Print the 48-digit Recovery Password immediately and store it in your password manager
(Get-BitLockerVolume -MountPoint "C:").KeyProtector |
    Where-Object KeyProtectorType -eq "RecoveryPassword" |
    Select-Object KeyProtectorId, RecoveryPassword
```

> **Watch out:** Suspend BitLocker (`Suspend-BitLocker -MountPoint "C:" -RebootCount 1`) before flashing UEFI/BIOS firmware or modifying Secure Boot keys. Failing to suspend causes BitLocker to lock into recovery mode on the next boot, requiring the 48-digit recovery password.

## Windows Defender, ASR Rules, and PUA Protection

Enable Defender cloud protection, Potentially Unwanted Application (PUA) blocking, Network Protection, and safe Attack Surface Reduction (ASR) rules.

`[ROOT]`
```powershell
# 1. Enable Cloud Protection, PUA Blocking, and Network Protection
Set-MpPreference -MAPSReporting Advanced `
    -SubmitSamplesConsent SendSafeSamples `
    -PUAProtection Enabled `
    -EnableNetworkProtection Enabled `
    -CloudBlockLevel High

# 2. Enable high-signal, developer-safe ASR rules (1 = Block, 2 = Audit)
$blockRules = @(
    "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2", # Block credential stealing from lsass.exe
    "be9ba2d9-53ea-4cdc-84e5-9b1eeee46550", # Block executable content from email client and webmail
    "d4f940ab-401b-4efc-aadc-ad5f3c50688a", # Block all Office applications from creating child processes
    "3b576869-a4ec-4529-8536-b80a7769e899", # Block Office applications from creating executable content
    "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84", # Block Office applications from injecting code into other processes
    "e6db77e5-3df2-4cf1-b95a-636979351e5b", # Block persistence through WMI event subscription
    "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4"  # Block untrusted and unsigned processes that run from USB
)

foreach ($rule in $blockRules) {
    Add-MpPreference -AttackSurfaceReductionRules_Ids $rule -AttackSurfaceReductionRules_Actions Enabled
}

# Audit rule for obfuscated scripts first so local toolchains do not break unexpectedly
Add-MpPreference -AttackSurfaceReductionRules_Ids "5beb7efe-fd9a-4556-801d-275e5ffc04cc" -AttackSurfaceReductionRules_Actions AuditMode
```

Inspect ASR audit/block hits in Event Viewer:

`[ROOT]`
```powershell
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-Windows Defender/Operational'
    Id        = 1121, 1122
    StartTime = (Get-Date).AddDays(-7)
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message | Format-Table -Wrap
```

## Core Isolation, HVCI, and LSA Protection

Verify virtualization-based security (VBS), Hypervisor-Protected Code Integrity (HVCI), and LSA PPL protection. Modern Windows 11 builds support VBS/HVCI alongside WSL2 and Hyper-V natively.

`[ROOT]` `[REBOOT]`
```powershell
# Check current VBS/HVCI/Credential Guard status
Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard |
    Select-Object VirtualizationBasedSecurityStatus, SecurityServicesConfigured, SecurityServicesRunning

# Enable LSA Protection (RunAsPPL)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -Value 1 -Type DWord

# Enable HVCI (Memory Integrity) via registry (takes effect on reboot)
$hvciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
New-Item -Path $hvciPath -Force | Out-Null
Set-ItemProperty -Path $hvciPath -Name "Enabled" -Value 1 -Type DWord
```

> **Watch out:** Enabling HVCI blocks unsigned or legacy kernel drivers (for example, old virtual COM port drivers or outdated anti-cheat/VPN drivers). Verify driver compatibility before rebooting by running `Get-WinEvent -LogName Microsoft-Windows-CodeIntegrity/Operational -MaxEvents 20` or checking **Windows Security -> Device Security -> Core Isolation -> Memory Integrity** which lists incompatible drivers upfront.

## Network, Firewall, and Protocol Hardening

Eliminate legacy LAN poisoning vectors (LLMNR, SMBv1, NetBIOS) and enforce default-deny inbound firewall rules while keeping WSL2/Hyper-V virtual switch interfaces functional.

`[ROOT]`
```powershell
# 1. Enforce Windows Firewall enabled on all profiles (Inbound Block, Outbound Allow)
Set-NetFirewallProfile -Profile Domain,Private,Public `
    -Enabled True `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Allow

# 2. Disable SMBv1 client/server and block insecure guest SMB fallback
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue
Set-SmbClientConfiguration -RequireSecuritySignature $true -EnableInsecureGuestLogons $false -Force

# 3. Disable LLMNR (mitigates local network credential capture on hotel/coffee-shop Wi-Fi)
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0 -Type DWord

# 4. Enable DNS over HTTPS (DoH) on Windows 11 for Cloudflare/Quad9 on public networks (example for Wi-Fi)
# netsh dns show encryption
# Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("1.1.1.1", "9.9.9.9")
```

## Local Account, UAC, and Execution Hygiene

Separate daily non-admin browsing/coding from local Administrator privilege where practical, keep UAC on the secure desktop, and block unauthenticated RDP.

`[ROOT]`
```powershell
# 1. Ensure UAC prompts on the Secure Desktop for Admin elevation
$uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $uacKey -Name "EnableLUA" -Value 1 -Type DWord
Set-ItemProperty -Path $uacKey -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWord
Set-ItemProperty -Path $uacKey -Name "PromptOnSecureDesktop" -Value 1 -Type DWord

# 2. Disable Remote Desktop if the workstation is not an explicit RDP target
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -Type DWord

# 3. Enable PowerShell Script Block Logging locally for incident visibility
$sbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
New-Item -Path $sbPath -Force | Out-Null
Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord

# 4. Require NTLMv2 only (refuse LM and NTLMv1)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5 -Type DWord
```

## Hardening Verification Checklist

`[ROOT]`
```powershell
# 1. Confirm BitLocker protection is On for C:
Get-BitLockerVolume -MountPoint "C:" | Select-Object MountPoint, EncryptionMethod, VolumeStatus, ProtectionStatus

# 2. Confirm Defender Real-Time, Network Protection, PUA, and ASR rules
Get-MpComputerStatus | Select-Object AMServiceEnabled, RealTimeProtectionEnabled, BehaviorMonitorEnabled, AntivirusSignatureLastUpdated
(Get-MpPreference).AttackSurfaceReductionRules_Ids.Count

# 3. Confirm Firewall profiles are all Enabled with Inbound Block
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction

# 4. Confirm SMBv1 is disabled and SMB signing is required
Get-SmbClientConfiguration | Select-Object RequireSecuritySignature, EnableInsecureGuestLogons
```
