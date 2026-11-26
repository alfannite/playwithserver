<#
.SYNOPSIS
    Safely shuts down WSL2 and compacts one or all ext4.vhdx virtual disks to reclaim host space.
.DESCRIPTION
    Discovers registered WSL2 distributions from HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss,
    runs 'wsl --shutdown', and compacts each ext4.vhdx using Optimize-VHD (Hyper-V module) or falls
    back cleanly to diskpart when running on Windows Home / without Hyper-V management tools.
    Safety tags: [ROOT] [DESTRUCTIVE] (terminates all running WSL processes before compaction).
.PARAMETER Distro
    Name of a single WSL distribution to compact (as shown by 'wsl -l -q').
.PARAMETER All
    Compact ext4.vhdx for every registered WSL2 distribution.
.PARAMETER DryRun
    List discovered VHDX files and current sizes without shutting down WSL or compacting.
.EXAMPLE
    .\wsl2-compact-vhdx.ps1 -All
.EXAMPLE
    .\wsl2-compact-vhdx.ps1 -Distro Ubuntu-24.04
#>
[CmdletBinding(DefaultParameterSetName = 'All')]
param(
    [Parameter(ParameterSetName = 'Single', Mandatory)]
    [string]$Distro,

    [Parameter(ParameterSetName = 'All')]
    [switch]$All,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $DryRun -and -not $IsAdmin) {
    throw 'Administrator privileges are required to compact VHDX files. Re-run in an elevated PowerShell.'
}

$LxssKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
if (-not (Test-Path $LxssKey)) {
    throw 'No WSL registry entries found under HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss.'
}

$Targets = @()
Get-ChildItem $LxssKey | ForEach-Object {
    $Props = Get-ItemProperty $_.PSPath
    if (-not $Props.PSObject.Properties['BasePath'] -or -not $Props.PSObject.Properties['DistributionName']) {
        return
    }
    $Name = $Props.DistributionName
    $BasePath = $Props.BasePath -replace '^\\\\\?\\', ''
    $Vhdx = Join-Path $BasePath 'ext4.vhdx'

    if (Test-Path $Vhdx) {
        if ($PSCmdlet.ParameterSetName -eq 'Single' -and $Name -ne $Distro) {
            return
        }
        $Targets += [PSCustomObject]@{
            Name = $Name
            Path = $Vhdx
            SizeGB = [Math]::Round((Get-Item $Vhdx).Length / 1GB, 2)
        }
    }
}

if ($Targets.Count -eq 0) {
    throw "No matching WSL2 ext4.vhdx files found."
}

Write-Host 'Discovered WSL2 VHDX target(s):' -ForegroundColor Cyan
$Targets | Format-Table Name, SizeGB, Path -AutoSize

if ($DryRun) {
    Write-Host '[dry-run] Exiting without shutting down WSL or modifying disks.' -ForegroundColor Yellow
    exit 0
}

Write-Host 'Shutting down all WSL instances (wsl --shutdown)...' -ForegroundColor Yellow
& wsl.exe --shutdown
Start-Sleep -Seconds 3

$HasOptimizeVhd = [bool](Get-Command Optimize-VHD -ErrorAction SilentlyContinue)

foreach ($Target in $Targets) {
    $BeforeBytes = (Get-Item $Target.Path).Length
    Write-Host "Compacting '$($Target.Name)' ($($Target.Path))..." -ForegroundColor Cyan

    if ($HasOptimizeVhd) {
        Optimize-VHD -Path $Target.Path -Mode Full
    } else {
        $DiskpartScript = New-TemporaryFile
        try {
            @(
                "select vdisk file=""$($Target.Path)"""
                'attach vdisk readonly'
                'compact vdisk'
                'detach vdisk'
                'exit'
            ) | Set-Content -Path $DiskpartScript.FullName -Encoding ASCII
            & diskpart.exe /s $DiskpartScript.FullName | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "diskpart failed with exit code $LASTEXITCODE on $($Target.Path)"
            }
        } finally {
            Remove-Item -Force -ErrorAction SilentlyContinue $DiskpartScript.FullName
        }
    }

    $AfterBytes = (Get-Item $Target.Path).Length
    $SavedMB = [Math]::Round(($BeforeBytes - $AfterBytes) / 1MB, 1)
    Write-Host ("  Before: {0:N2} GB | After: {1:N2} GB | Reclaimed: {2:N1} MB" -f `
        ($BeforeBytes / 1GB), ($AfterBytes / 1GB), $SavedMB) -ForegroundColor Green
}
