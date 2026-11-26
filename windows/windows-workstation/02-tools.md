# Windows Workstation Admin Tools

Deep operational guide to high-signal Windows 10/11 Pro/Enterprise CLI and Sysinternals tools: `winget`, `scoop`, `Procmon`, `Process Explorer`, `TCPView`, `Autoruns`, `RAMMap`, `PsExec`, `Handle`, `Sigcheck`, `LiveKd`, `netsh`, and `DISM`/`sfc`.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [Tooling Overview Matrix](#tooling-overview-matrix)
- [Package Management with winget and scoop](#package-management-with-winget-and-scoop)
- [Sysinternals Suite Installation and Core Tools](#sysinternals-suite-installation-and-core-tools)
- [Process, Handle, and Memory Diagnostics](#process-handle-and-memory-diagnostics)
- [Startup, Binary Integrity, and Remote Execution](#startup-binary-integrity-and-remote-execution)
- [Advanced Networking with netsh](#advanced-networking-with-netsh)
- [OS Image Servicing with DISM and sfc](#os-image-servicing-with-dism-and-sfc)

## Tooling Overview Matrix

| Category | Tool | Install Method | Primary Use Case |
| --- | --- | --- | --- |
| Package Mgmt | `winget` | Built-in (App Installer) | System-wide MSIs/EXEs, export/import manifests, pinning |
| Package Mgmt | `scoop` | `irm get.scoop.sh \| iex` | Portable CLI shims without UAC prompts |
| Process Trace | `procmon64` | `winget install Microsoft.Sysinternals.Suite` | Real-time file, registry, and process syscall tracing |
| Process Tree | `procexp64` | `winget install Microsoft.Sysinternals.Suite` | DLLs, handles, GPU/I/O graphs, VirusTotal hash checks |
| Sockets | `tcpview64` / `tcpvcon64` | `winget install Microsoft.Sysinternals.Suite` | Live TCP/UDP connection monitoring and PID mapping |
| Persistence | `autoruns64` / `autorunsc64` | `winget install Microsoft.Sysinternals.Suite` | Exhaustive startup, scheduled task, driver, and shell extension audit |
| Memory | `RAMMap64` | `winget install Microsoft.Sysinternals.Suite` | Physical RAM breakdown (Standby, Driver Locked, Metafile, Nonpaged Pool) |
| File Locks | `handle64` | `winget install Microsoft.Sysinternals.Suite` | Identify which PID locks a file/directory |
| Signing/Malware | `sigcheck64` | `winget install Microsoft.Sysinternals.Suite` | Authenticode verification, unsigned binary scans, VirusTotal lookup |
| Network Proxy/Trace | `netsh` | Built-in | Port forwarding (`portproxy`), Wi-Fi keys, zero-install ETW packet capture |

## Package Management with winget and scoop

### winget Real-World Usages `[NON-ROOT]` / `[ROOT]`

```powershell
# 1. Search with exact IDs and install silently accepting all agreements
winget search --name "PowerShell" --source winget
winget install --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements

# 2. Export and import a reproducible workstation package manifest
winget export -o C:\Configs\workstation-apps.json --accept-source-agreements
winget import -i C:\Configs\workstation-apps.json --accept-package-agreements --accept-source-agreements --ignore-unavailable

# 3. Pin a package to prevent accidental major upgrades (e.g., Terraform or Docker Desktop)
winget pin add --id Hashicorp.Terraform --blocking
winget pin list

# 4. Upgrade all non-pinned packages cleanly
winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements
```

> **Watch out:** Running `winget upgrade --all` without `--include-unknown` skips packages whose installed version string does not match the winget catalog, while running it **with** `--include-unknown` can overwrite custom side-loaded builds (such as manually compiled OpenSSL or older Python point releases). Pin sensitive runtimes with `winget pin add --id <Id> --blocking` first.

### scoop Real-World Usages `[NON-ROOT]`

```powershell
# 1. Install portable DevOps/infra CLIs cleanly without polluting System PATH
scoop install kubectl helm terraform aws azure-cli gh age sops

# 2. Update scoop manifests and upgrade all installed shims
scoop update *

# 3. Clean up old cached versions and verify shim/environment health
scoop cleanup *
scoop checkup
```

> **Watch out:** Scoop installs into `%USERPROFILE%\scoop\shims` and runs completely non-elevated. If an elevated PowerShell session does not find your scoop binaries, verify `%USERPROFILE%\scoop\shims` is present in the user's `PATH` (when running under a separate local admin account via UAC, the user profile switches and your standard user's `scoop\shims` is not on the admin account's `PATH`).

## Sysinternals Suite Installation and Core Tools

### Install `[ROOT]`

```powershell
# Install full Sysinternals Suite via winget (adds binaries to PATH via App Execution Aliases)
winget install --id Microsoft.Sysinternals.Suite --source winget --accept-package-agreements --accept-source-agreements

# Alternative portable user-level install via scoop
# scoop bucket add sysinternals && scoop install sysinternals
```

> **Watch out:** Every Sysinternals CLI binary prompts with a GUI EULA dialog on first run, which hangs headless or automated scripts. Always pass `-accepteula` on CLI invocations (`handle64 -accepteula`, `autorunsc64 -accepteula`, `sigcheck64 -accepteula`).

## Process, Handle, and Memory Diagnostics

### Process Monitor (procmon64) `[ROOT]`

Real-time kernel-level tracing of file system, registry, network, and process/thread activity.

```powershell
# 1. Capture silently to a backing PML file (crucial for long captures so RAM does not fill)
procmon64.exe /AcceptEula /Quiet /Minimized /BackingFile C:\Temp\trace.pml

# 2. Stop an active headless Procmon capture cleanly
procmon64.exe /Terminate

# 3. Convert a captured PML file to CSV for PowerShell filtering (e.g., find ACCESS DENIED)
procmon64.exe /OpenLog C:\Temp\trace.pml /SaveAs C:\Temp\trace.csv
Import-Csv C:\Temp\trace.csv | Where-Object Result -eq "ACCESS DENIED" | Select-Object -First 30 Process Name, Operation, Path
```

> **Watch out:** Leaving Procmon running without `/BackingFile` stores every event in virtual memory (paging file), which can exhaust RAM and freeze a workstation within minutes. Always use `/BackingFile` and enable **Drop Filtered Events** when diagnosing intermittent issues.

### Process Explorer (procexp64) & TCPView (tcpvcon64) `[ROOT]`

```powershell
# 1. Launch Process Explorer elevated (required to inspect PPL/SYSTEM processes and full handles)
Start-Process procexp64.exe -Verb RunAs

# 2. List all active TCP/UDP endpoints with process names in CSV format via CLI TCPView
tcpvcon64.exe -accepteula -a -n -c

# 3. Filter active outbound connections for a specific process (e.g., ssh or python)
tcpvcon64.exe -accepteula -a -n -c | ConvertFrom-Csv -Header Proto,Proc,PID,State,Local,Remote |
    Where-Object State -eq "ESTABLISHED"
```

### Handle (handle64) `[ROOT]`

Locate the exact PID holding an open lock on a file, folder, or volume when Windows refuses to delete or eject it.

```powershell
# 1. Find which process locks a specific file or directory path
handle64.exe -accepteula -nobanner "C:\Projects\app\dist"

# 2. List all open handles held by a specific PID (e.g., PID 4120)
handle64.exe -accepteula -nobanner -p 4120

# 3. Summarize handle counts by type across processes (spot handle leaks)
handle64.exe -accepteula -s -p w3wp.exe
```

> **Watch out:** `handle64.exe -c <handle> -p <pid>` can forcibly close a handle inside a running process, but closing a file handle underneath an active process can corrupt in-flight writes or crash the application. Identify the owning process and stop it gracefully whenever possible.

### RAMMap (RAMMap64) `[ROOT]`

Diagnose invisible memory leaks where Task Manager shows 90% RAM used but running processes only sum to 30% (typically **Nonpaged Pool** driver leaks, **Driver Locked** Hyper-V/WSL allocations, or **Metafile** NTFS cache bloat).

```powershell
# 1. Launch RAMMap GUI for full Use Counts / Processes / File Summary inspection
Start-Process RAMMap64.exe -Verb RunAs

# 2. Capture a physical memory snapshot headlessly for offline analysis
RAMMap64.exe -accepteula C:\Temp\ram-snapshot.rmp

# 3. Flush Standby List (reclaim cached pages safely when testing cold I/O performance)
RAMMap64.exe -accepteula -Et
```

## Startup, Binary Integrity, and Remote Execution

### Autoruns CLI (autorunsc64) `[ROOT]`

Audit every persistence vector (Run keys, Scheduled Tasks, Services, Drivers, WMI Event Consumers, LSA providers, Browser/Explorer extensions).

```powershell
# 1. Audit all non-Microsoft signed or unsigned persistence entries across the entire OS, formatted as CSV
autorunsc64.exe -accepteula -a * -c -h -s -v -m -o C:\Temp\autoruns.csv

# 2. Inspect only Scheduled Tasks (-t) and Services (-s) hiding verified Microsoft entries (-m)
autorunsc64.exe -accepteula -a ts -m -s

# 3. Diff current persistence state against a known-good baseline
autorunsc64.exe -accepteula -a * -c -m > C:\Temp\current.csv
Compare-Object (Get-Content C:\Baselines\autoruns-clean.csv) (Get-Content C:\Temp\current.csv)
```

> **Watch out:** Passing `-v` submits file hashes to VirusTotal and requires accepting VirusTotal terms (`-vt` flag). On sensitive corporate networks with data-loss policies, omit `-v` and validate signatures locally with `-s` only.

### Sigcheck (sigcheck64) `[ROOT]`

Verify Authenticode signatures, detect unsigned binaries, and inspect PE metadata.

```powershell
# 1. Scan a directory recursively for unsigned executables/DLLs (-u = unsigned, -e = executable images only, -s = recurse)
sigcheck64.exe -accepteula -u -e -s "C:\Program Files\VendorApp"

# 2. Check certificate chain, SHA256 hash, and timestamp on a downloaded installer
sigcheck64.exe -accepteula -i -h "C:\Users\$env:USERNAME\Downloads\installer.exe"

# 3. Audit Windows trusted root certificate store against Microsoft's official CTL (detect rogue root CAs)
sigcheck64.exe -accepteula -tuv
```

### PsExec (PsExec64) and LiveKd (livekd64) `[ROOT]`

```powershell
# 1. Launch an interactive shell as NT AUTHORITY\SYSTEM locally for deep ACL/registry debugging
PsExec64.exe -accepteula -i -s pwsh.exe

# 2. Run a one-off diagnostic command on a remote lab machine (only where SMB/ADMIN$ is permitted)
PsExec64.exe -accepteula \\10.20.10.15 -h powershell.exe -Command "Get-Service sshd"

# 3. Capture a live kernel memory dump without bugchecking/rebooting the workstation (requires Windows Debugging Tools / WinDbg)
livekd64.exe -accepteula -o C:\Temp\live-kernel.dmp -ml
```

> **Watch out:** `PsExec` authenticates over SMB (`ADMIN$`) and installs a temporary `PSEXESVC` service, triggering immediate EDR alerts in hardened enterprise environments. Prefer PowerShell Remoting (WinRM HTTPS) or OpenSSH for routine remote management; reserve `PsExec -i -s` for local SYSTEM-context troubleshooting.

## Advanced Networking with netsh

Although PowerShell `NetTCPIP` cmdlets replace most `netsh` commands, three `netsh` subcommands remain uniquely indispensable on Windows workstations.

### Port Forwarding with interface portproxy `[ROOT]`

Forward local or LAN ports to WSL2, Hyper-V VMs, or remote hosts natively via IP Helper (`iphlpsvc`).

```powershell
# 1. Forward host port 8080 on all interfaces to a VM/WSL2 guest at 172.24.10.5:8080
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=8080 connectaddress=172.24.10.5 connectport=8080

# 2. Display all active portproxy rules
netsh interface portproxy show all

# 3. Remove a rule when finished
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=8080
```

### Inspect Saved Wi-Fi Profiles and Pre-Shared Keys `[ROOT]`

```powershell
# List saved SSID profiles
netsh wlan show profiles

# Reveal cleartext WPA2/WPA3 key for a specific SSID
netsh wlan show profile name="CorpLab-5G" key=clear | Select-String "SSID name|Authentication|Key Content"
```

### Zero-Install Packet Capture with netsh trace `[ROOT]`

Capture full packets plus Windows network stack events on any machine without installing Npcap or Wireshark.

```powershell
# 1. Start a circular 250 MB capture filtered to a target IP
netsh trace start capture=yes IPv4.Address=10.20.10.15 maxsize=250 filemode=circular tracefile=C:\Temp\nettrace.etl

# 2. Reproduce the network issue, then stop and merge the trace
netsh trace stop

# 3. Convert ETL to standard PCAPNG for Wireshark using built-in pktmon (Windows 10 2004+ / Windows 11)
pktmon etl2pcap C:\Temp\nettrace.etl -o C:\Temp\nettrace.pcapng
```

> **Watch out:** `netsh trace stop` can take 30–90 seconds while correlating symbols and flushing buffers; do not kill the terminal early or the `.etl` file will be truncated and unreadable. For quick modern captures on Windows 10 2004+ / 11, `pktmon start --capture --pkt-size 0` followed by `pktmon stop` and `pktmon etl2pcap PktMon.etl` is faster and supports real-time stdout logging (`--log-mode real-time`).

## OS Image Servicing with DISM and sfc

Verify and repair system file integrity and WinSxS component store corruption after driver crashes or failed updates.

### Install `[ROOT]`

Built into Windows 10/11.

### Real-World Usages `[ROOT]`

```powershell
# 1. Check component store health rapidly (read-only)
DISM /Online /Cleanup-Image /CheckHealth

# 2. Deep scan and repair component store using Windows Update sources
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth

# 3. Verify and repair all protected Windows system files using the repaired WinSxS store
sfc /scannow

# 4. Inspect WinSxS disk usage and clean superseded update components
DISM /Online /Cleanup-Image /AnalyzeComponentStore
DISM /Online /Cleanup-Image /StartComponentCleanup
```

> **Watch out:** Always run `DISM /Online /Cleanup-Image /RestoreHealth` **before** `sfc /scannow`. `sfc` repairs protected files by copying clean binaries out of WinSxS—if WinSxS itself is corrupted, `sfc` reports unfixable errors until DISM repairs the store first.
