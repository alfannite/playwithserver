# WSL2 Security Hardening

Practical security controls for WSL2 on Windows 10/11 workstations: Hyper-V Firewall integration, restricting Windows binary interop, protecting host credentials and NTFS mounts, SSH key hygiene, systemd service confinement, and keeping the WSL2 Linux kernel patched.

[← Back to Windows](../README.md) | [Home](../../README.md)

## Contents

- [WSL2 Threat Model and Hardening Guardrails](#wsl2-threat-model-and-hardening-guardrails)
- [Hyper-V Firewall and Mirrored Network Controls](#hyper-v-firewall-and-mirrored-network-controls)
- [NTFS Automount and Interop Hardening](#ntfs-automount-and-interop-hardening)
- [Linux Account, Sudo, and SSH Key Hygiene](#linux-account-sudo-and-ssh-key-hygiene)
- [Kernel Patching and Container Isolation](#kernel-patching-and-container-isolation)
- [Hardening Verification Checklist](#hardening-verification-checklist)

## WSL2 Threat Model and Hardening Guardrails

A compromised process inside WSL2 runs with your **Windows user's privileges** whenever `interop` and `automount` are enabled—it can read `%USERPROFILE%` over `/mnt/c` and invoke `powershell.exe` or `cmd.exe`.

| Control | Recommended Setting | What Breaks If Over-Hardened |
| --- | --- | --- |
| Hyper-V Firewall (`firewall=true`) | Default Inbound Block, explicit Allow for needed ports | Blocking inbound ports stops LAN devices from reaching dev web servers in mirrored mode (intended!) |
| `automount` | Enabled with `metadata,umask=22,fmask=11` for dev distros; `enabled=false` for untrusted/sandbox distros | Disabling `automount` blocks reading/writing `C:` directly and breaks VS Code Remote-WSL bootstrap |
| `interop` | Enabled for primary dev distro; `enabled=false` for untrusted/sandbox distros | Disabling `interop` blocks `code .`, `clip.exe`, and `npiperelay.exe` |
| `sudo` | Require password (do not grant passwordless `ALL=(ALL) NOPASSWD: ALL` globally) | Interactive scripts prompt once for sudo password |
| WSL2 Kernel | Keep updated via `wsl --update` | Stale Linux kernels miss container escape and netfilter CVEs |

## Hyper-V Firewall and Mirrored Network Controls

When `firewall=true` is set in `%USERPROFILE%\.wslconfig` (enabled by default in WSL 2.x), Windows enforces **Hyper-V Firewall** rules on WSL2 VM traffic independently of guest `iptables`/`nftables`.

`[ROOT]`
```powershell
# 1. Inspect WSL2 Hyper-V Firewall VM creator ID and default inbound/outbound actions
$wslVmCreatorId = "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}"
Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name $wslVmCreatorId |
    Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction, LoopbackEnabled

# 2. Enforce strict DefaultInboundAction = Block while permitting outbound traffic
Set-NetFirewallHyperVVMSetting -Name $wslVmCreatorId `
    -Enabled True `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Allow

# 3. Allow a specific inbound port ONLY from Private LAN when intentionally testing from another device
New-NetFirewallHyperVRule -Name "WSL-Dev-8080-Private" `
    -DisplayName "WSL2 Dev Server 8080 (Private LAN)" `
    -Direction Inbound `
    -VMCreatorId $wslVmCreatorId `
    -Protocol TCP `
    -LocalPorts 8080 `
    -Profile Private `
    -Action Allow

# 4. Audit all active Hyper-V Firewall rules applied to WSL2
Get-NetFirewallHyperVRule -VMCreatorId $wslVmCreatorId |
    Format-Table Name, Direction, Protocol, LocalPorts, Action, Enabled
```

> **Watch out:** In `networkingMode=mirrored`, services inside WSL2 that bind to `0.0.0.0` become exposed on your Windows host interfaces if Hyper-V Firewall inbound rules permit them. Bind local-only development databases (PostgreSQL, Redis, Elasticsearch) explicitly to `127.0.0.1` (`-p 127.0.0.1:5432:5432`) so they are never exposed on hotel or corporate Wi-Fi even if a firewall rule is misconfigured.

## NTFS Automount and Interop Hardening

### Isolate Untrusted or Sandbox Distros `[ROOT]`

When running untrusted third-party build scripts, malware samples, or random repositories, create a dedicated isolated WSL2 distro with Windows filesystem mounts and Windows binary execution completely disabled in `/etc/wsl.conf`:

```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true

[automount]
enabled=false

[interop]
enabled=false
appendWindowsPath=false

[user]
default=sandbox
EOF
```

### Primary Dev Distro: Strip World-Writable/Executable Bits on /mnt/c `[ROOT]`

By default without `umask`/`fmask`, every file on `/mnt/c` appears as `0777` inside Linux, breaking SSH key permission checks and allowing accidental execution of arbitrary Windows files. Enforce clean mount flags in `/etc/wsl.conf`:

```ini
[automount]
enabled=true
root=/mnt/
options="metadata,umask=22,fmask=11"
```

## Linux Account, Sudo, and SSH Key Hygiene

Configure standard Linux hardening inside your WSL2 distribution.

`[ROOT]`
```bash
# 1. Verify root account has no usable password (use sudo from non-root user)
sudo passwd -l root

# 2. Verify no broad NOPASSWD rules exist in /etc/sudoers.d/
sudo grep -rn "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null

# 3. Restrict SSH directory and private keys if storing keys directly inside WSL2
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* ~/.ssh/config 2>/dev/null
chmod 644 ~/.ssh/*.pub 2>/dev/null

# 4. Ensure sshd is NOT running inside WSL2 unless explicitly required
systemctl is-active ssh sshd 2>/dev/null || echo "sshd inactive (good)"
```

> **Watch out:** Because WSL2 shares the Windows host's encryption boundary, unencrypted `ext4.vhdx` files on `C:` or `D:` can be mounted offline if your laptop is stolen. Always enable **BitLocker** on every drive storing WSL2 VHDX images (including `D:\WSL\`).

## Kernel Patching and Container Isolation

### Keep the WSL2 Kernel and Store Package Current `[ROOT]`

```powershell
# Check current WSL2 and kernel version and apply Microsoft security updates
wsl --version
wsl --update
wsl --shutdown
```

### Harden Native Docker Daemon Inside WSL2 `[ROOT]`

Configure `/etc/docker/daemon.json` to prevent runaway disk logs and disable legacy userland proxy bloat:

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "no-new-privileges": true
}
EOF
sudo systemctl restart docker
```

## Hardening Verification Checklist

Windows host (`[ROOT]`):

```powershell
# 1. Confirm WSL2 kernel is up to date
wsl --version

# 2. Confirm BitLocker is protecting both C: and any secondary WSL drive (e.g., D:)
Get-BitLockerVolume | Select-Object MountPoint, ProtectionStatus, EncryptionMethod

# 3. Confirm Hyper-V Firewall is Enabled with DefaultInboundAction = Block
Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" |
    Select-Object Enabled, DefaultInboundAction, DefaultOutboundAction
```

Inside WSL2 Linux (`[NON-ROOT]`):

```bash
# 4. Verify listening sockets are bound to 127.0.0.1 rather than 0.0.0.0 where appropriate
ss -tulnp

# 5. Verify /mnt/c mount options include metadata and umask=22
mount | grep '/mnt/c'
```
