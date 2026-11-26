<#
.SYNOPSIS
    Bootstraps a Windows 10/11 or Server workstation with core admin CLI tools via winget.
.DESCRIPTION
    Installs PowerShell 7, Git, Windows Terminal, Sysinternals Suite, and modern CLI utilities
    non-interactively using winget with exact package IDs.
    Safety tags: [NON-ROOT] / [ROOT] (some installers prompt for UAC if not elevated).
.PARAMETER SkipOptional
    Install only core operational tools (PowerShell 7, Git, Windows Terminal, Sysinternals).
.PARAMETER DryRun
    Print winget commands without installing packages.
.EXAMPLE
    .\windows-ops-bootstrap.ps1
.EXAMPLE
    .\windows-ops-bootstrap.ps1 -SkipOptional -DryRun
#>
[CmdletBinding()]
param(
    [switch]$SkipOptional,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not installed or not in PATH. Install App Installer from Microsoft Store or GitHub winget-cli.'
}

$CorePackages = @(
    'Microsoft.PowerShell'
    'Microsoft.WindowsTerminal'
    'Git.Git'
    'Microsoft.Sysinternals.Suite'
    'OpenJS.NodeJS.LTS'
)

$OptionalPackages = @(
    'jqlang.jq'
    'BurntSushi.ripgrep.MSVC'
    'sharkdp.fd'
    'sharkdp.bat'
    'junegunn.fzf'
    'gerardog.gsudo'
    'dorssel.usbipd-win'
    'WireGuard.WireGuard'
    'Tailscale.Tailscale'
    '7zip.7zip'
)

$Packages = @($CorePackages)
if (-not $SkipOptional) {
    $Packages += $OptionalPackages
}

Write-Host "Installing $($Packages.Count) package(s) via winget..." -ForegroundColor Cyan

$Failed = @()
foreach ($Id in $Packages) {
    $ArgsList = @(
        'install'
        '--id', $Id
        '--exact'
        '--source', 'winget'
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--silent'
    )

    if ($DryRun) {
        Write-Host "[dry-run] winget $($ArgsList -join ' ')"
        continue
    }

    Write-Host "-> $Id" -ForegroundColor Gray
    & winget @ArgsList
    # Exit codes: 0 = installed, -1978335189 (0x8A15002B) = already installed & no upgrade available
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warning "winget exited with code $LASTEXITCODE for $Id"
        $Failed += $Id
    }
}

if (-not $DryRun) {
    Write-Host "`nBootstrap finished. Open a new Windows Terminal (PowerShell 7) session to refresh PATH." -ForegroundColor Green
    if ($Failed.Count -gt 0) {
        Write-Warning "Review failed packages: $($Failed -join ', ')"
        exit 1
    }
}
