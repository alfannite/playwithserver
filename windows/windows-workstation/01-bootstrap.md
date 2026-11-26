# Windows Workstation Bootstrap

First-boot setup for a Windows 10/11 Pro or Enterprise engineering and systems administration workstation: `winget` and `scoop` package managers, PowerShell 7 with PSReadLine and profile scaffolding, Windows Terminal, OpenSSH client with `ssh-agent`, Git, and safe non-destructive debloating that preserves Windows Update, Microsoft Store, Defender, and WSL2.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Core Package Managers winget and scoop](#core-package-managers-winget-and-scoop)
- [PowerShell 7, PSReadLine, and Profile Setup](#powershell-7-psreadline-and-profile-setup)
- [OpenSSH Client and ssh-agent Service](#openssh-client-and-ssh-agent-service)
- [Base Admin Toolkit Installation](#base-admin-toolkit-installation)
- [Safe Non-Destructive Debloat](#safe-non-destructive-debloat)
- [Developer Mode, Long Paths, and RSAT](#developer-mode-long-paths-and-rsat)
- [Post-Bootstrap Verification](#post-bootstrap-verification)

## Core Package Managers winget and scoop

Windows 11 includes `winget` via App Installer; on fresh Windows 10/11 images, update the package source agreements first. Pair `winget` (system-wide MSIs/EXEs) with `scoop` (portable CLI shims without UAC prompts).

### Update winget and Bootstrap scoop `[NON-ROOT]`

```powershell
# Verify winget version and accept source agreements once
winget --version
winget source update --accept-source-agreements

# Install scoop (user-scoped, no admin required, installs cleanly into %USERPROFILE%\scoop)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

# Add essential scoop buckets
scoop bucket add main
scoop bucket add extras
scoop bucket add sysinternals
```

> **Watch out:** Never run `scoop` inside an elevated Administrator shell unless passing `-RunAsAdmin` during initial install—running scoop as Administrator creates root-owned shims and breaks non-elevated updates. Use `winget` for system-wide installers and `scoop` strictly from a standard user terminal.

## PowerShell 7, PSReadLine, and Profile Setup

Replace Windows PowerShell 5.1 as your interactive shell with PowerShell 7 (`pwsh`), predictive history via `PSReadLine`, and a clean `$PROFILE`.

### Install PowerShell 7 and Windows Terminal `[ROOT]`

```powershell
winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.WindowsTerminal --source winget --accept-package-agreements --accept-source-agreements
```

### Configure PSReadLine and Profile inside pwsh `[NON-ROOT]`

Open `pwsh` and run:

```powershell
# Install/update modern PSReadLine and completion modules
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name PSReadLine -Scope CurrentUser -Force
Install-Module -Name Terminal-Icons -Scope CurrentUser -Force
Install-Module -Name CompletionPredictor -Scope CurrentUser -Force

# Create profile directory and file if missing
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

# Write a fast, high-signal $PROFILE
@'
# PSReadLine predictive IntelliSense & history search
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -MaximumHistoryCount 20000
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# High-signal admin helpers
function which($cmd) { (Get-Command $cmd -ErrorAction SilentlyContinue).Source }
function ll { Get-ChildItem -Force @args }
function ports {
    Get-NetTCPConnection -State Listen |
        Select-Object LocalAddress, LocalPort, OwningProcess,
            @{N='Process';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} |
        Sort-Object LocalPort | Format-Table -AutoSize
}

# Ensure Windows OpenSSH client takes precedence over Git's bundled ssh.exe
$env:GIT_SSH = "$env:SystemRoot\System32\OpenSSH\ssh.exe"
'@ | Set-Content -Path $PROFILE -Encoding utf8
```

## OpenSSH Client and ssh-agent Service

Windows ships a native OpenSSH client (`C:\Windows\System32\OpenSSH\ssh.exe`) and a persistent `ssh-agent` Windows service that stores decrypted private keys securely in the Windows Registry using DPAPI across reboots.

### Enable OpenSSH Client and ssh-agent `[ROOT]`

```powershell
# Verify or install OpenSSH Client capability
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Enable and start the ssh-agent service
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
```

### Generate Ed25519 Key and Register with ssh-agent `[NON-ROOT]`

```powershell
# Generate a passphrase-protected Ed25519 keypair
ssh-keygen -t ed25519 -a 100 -C "$env:USERNAME@$env:COMPUTERNAME" -f "$env:USERPROFILE\.ssh\id_ed25519"

# Load key into persistent Windows ssh-agent (persists across reboots without re-entering passphrase)
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
ssh-add -L

# Point Git to native Windows OpenSSH so git push/pull uses ssh-agent automatically
git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"
```

> **Watch out:** Git for Windows bundles its own MSYS2 `ssh.exe` and `ssh-agent.exe` which cannot communicate with the Windows `ssh-agent` service. Setting `git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"` prevents repeated passphrase prompts during `git fetch`/`git push`.

## Base Admin Toolkit Installation

Install standard CLI and diagnostic tools in one reproducible pass.

`[ROOT]`
```powershell
$packages = @(
    "Git.Git",
    "Microsoft.Sysinternals.Suite",
    "Microsoft.VisualStudioCode",
    "7zip.7zip",
    "WiresharkFoundation.Wireshark",
    "jqlang.jq",
    "BurntSushi.ripgrep.MSVC",
    "sharkdp.fd",
    "junegunn.fzf",
    "MikeFarah.yq"
)

foreach ($pkg in $packages) {
    winget install --id $pkg --exact --source winget --accept-package-agreements --accept-source-agreements --silent
}
```

Export your workstation package manifest immediately after setup for reproducible rebuilds:

`[NON-ROOT]`
```powershell
winget export -o "$env:USERPROFILE\workstation-winget.json" --accept-source-agreements
```

## Safe Non-Destructive Debloat

Remove consumer bloatware and disable ads/consumer suggestions using supported AppX removal and documented policy keys—never run aggressive third-party debloat scripts that rip out `WindowsUpdate`, `Microsoft.WindowsStore`, `SecurityHealth`, or `XboxIdentityProvider` dependencies needed by WSL2/Winget.

### Remove Non-Essential Consumer AppX Packages `[ROOT]`

```powershell
# Safe allowlist of purely consumer apps to remove (leaves Store, AppInstaller/winget, Terminal, Calculator, Defender intact)
$bloatApps = @(
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GamingApp",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.People",
    "Microsoft.Todos",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.YourPhone",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Clipchamp.Clipchamp",
    "MicrosoftCorporationII.QuickAssist"
)

foreach ($app in $bloatApps) {
    Get-AppxPackage -AllUsers -Name $app | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $app |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}
```

### Disable Consumer Content, Start Ads, and Non-Essential Telemetry via Policy `[ROOT]`

```powershell
# Disable Cloud Consumer Features (stops Windows silently reinstalling Candy Crush / Spotify / etc.)
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding" -Value 1 -Type DWord

# Set Telemetry to minimum safe level (1 = Required/Basic on Pro; 0 = Security on Enterprise only)
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Type DWord

# Disable Start Menu web search / Bing results (keeps local search fast)
New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord

# Disable Advertising ID
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord
```

> **Watch out:** Never remove `Microsoft.DesktopAppInstaller`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`, or `Microsoft.WindowsStore`—doing so breaks `winget`, Windows Terminal updates, and WSL2 Store distribution updates. Avoid scripts that disable the `DiagTrack` or `wuauserv` services, as both can stall cumulative security updates and Windows Defender definition updates.

## Developer Mode, Long Paths, and RSAT

Enable NTFS long paths (>260 chars, critical for Node/Rust/Git repos), symlink creation without UAC (Developer Mode), and optional RSAT tools for managing Windows Servers.

`[ROOT]`
```powershell
# Enable Win32 long paths (>260 characters)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name "LongPathsEnabled" -Value 1 -Type DWord

# Enable Developer Mode (allows non-admin symlink creation for git/npm/cargo/scoop)
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" `
    -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord

# Optional: Install RSAT AD & DNS management tools for managing Windows Server fleets
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.Dns.Tools~~~~0.0.1.0
```

## Post-Bootstrap Verification

`[NON-ROOT]`
```powershell
# 1. Confirm PowerShell 7 and PSReadLine version
$PSVersionTable.PSVersion
Get-Module PSReadLine | Select-Object Name, Version

# 2. Confirm native OpenSSH client and loaded ssh-agent keys
Get-Command ssh | Select-Object Source
Get-Service ssh-agent | Select-Object Name, Status, StartType
ssh-add -l

# 3. Confirm winget, scoop, and Sysinternals availability
winget --version
scoop --version
Get-Command procexp64, procmon64, handle64 -ErrorAction SilentlyContinue | Select-Object Name, Source

# 4. Confirm LongPathsEnabled and Developer Mode
Get-ItemPropertyValue "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled
```
