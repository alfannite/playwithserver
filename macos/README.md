# macOS Administration Hub

Field guide for Darwin/macOS systems administration, BSD/macOS networking and security tooling, and running Apple Silicon or Intel Macs as 24/7 headless servers.

[← Home](../README.md)

## Variant Guides

| Variant | Target Scope | 01 Bootstrap | 02 Tools | 03 Tips & Tricks | 04 Hardening | 05 Troubleshooting |
| --- | --- | --- | --- | --- | --- | --- |
| `system-admin` | `launchd`/`launchctl`, `pmset`, `diskutil`/APFS, `tmutil`, `defaults` | [Bootstrap](system-admin/01-bootstrap.md) | [Tools](system-admin/02-tools.md) | [Tips & Tricks](system-admin/03-tips-tricks.md) | [Hardening](system-admin/04-hardening.md) | [Troubleshooting](system-admin/05-troubleshooting.md) |
| `networking-security` | `pfctl`, `scutil`, `networksetup`, `lsof`, DNS flush, SIP, FileVault, Gatekeeper | [Bootstrap](networking-security/01-bootstrap.md) | [Tools](networking-security/02-tools.md) | [Tips & Tricks](networking-security/03-tips-tricks.md) | [Hardening](networking-security/04-hardening.md) | [Troubleshooting](networking-security/05-troubleshooting.md) |
| `mac-as-server` | 24/7 headless Mac Mini, Brewfile, OrbStack/Colima, UTM, SSH/Screen Sharing | [Bootstrap](mac-as-server/01-bootstrap.md) | [Tools](mac-as-server/02-tools.md) | [Tips & Tricks](mac-as-server/03-tips-tricks.md) | [Hardening](mac-as-server/04-hardening.md) | [Troubleshooting](mac-as-server/05-troubleshooting.md) |

## Darwin / BSD vs GNU Linux Differences

macOS ships BSD userland utilities that diverge subtly from GNU coreutils on Linux. Scripts copied from Linux frequently break on these flags:

| Utility | GNU Linux Behavior | macOS / BSD Behavior | Portable / Fix |
| --- | --- | --- | --- |
| `sed -i` | `sed -i 's/foo/bar/g' file` | Requires explicit backup suffix: `sed -i '' 's/foo/bar/g' file` | Install `gnu-sed` (`gsed`) or use `perl -pi -e` |
| `date` | `date -d '2 days ago' +%F`, `date -d @1700000000` | `date -v-2d +%F`, `date -r 1700000000` | Install `coreutils` (`gdate`) for GNU flags |
| `stat` | `stat -c '%a %U:%G %s' file` | `stat -f '%Lp %Su:%Sg %z' file` | Use `gstat` from Homebrew `coreutils` |
| `readlink` | `readlink -f path` (canonicalize) | Supported on macOS 12.3+, missing on older macOS | Use `realpath` or Python `os.path.realpath` |
| `grep` | `grep -P` (PCRE) supported | `-P` unsupported in BSD `grep` | Use `rg` (ripgrep) or `ggrep` (`brew install grep`) |
| `ps` | `ps -ef`, `ps aux --sort=-%mem` | No `--sort`; use `ps aux -m` (mem) or `ps aux -r` (CPU) | Use `ps -axo pid,ppid,%cpu,%mem,comm -r` |
| `xargs` | `xargs -r` (no-run-if-empty) | `-r` ignored/unneeded (macOS `xargs` skips empty input by default) | Avoid `-r` for portability or use `gxargs` |
| `base64` | `base64 -w 0` (no wrap), `base64 -d` | No `-w`; output is unwrapped by default; `-D` or `-d` to decode | `base64 \| tr -d '\n'` |
| `tar` | Standard POSIX/GNU tar | Adds macOS AppleDouble `._*` extended attribute files | Set `COPYFILE_DISABLE=1 tar -czf ...` |
| `free` / `/proc` | `/proc/meminfo`, `free -h` | No `/proc` filesystem | Use `vm_stat`, `memory_pressure`, `sysctl hw.memsize` |
| `ss` / `ip` | `ss -tulpn`, `ip addr` | Not present | Use `lsof -nP -iTCP -sTCP:LISTEN`, `ifconfig`, `scutil --nwi` |

> **Watch out:** Do not prepend Homebrew's `gnubin` directory ahead of `/usr/bin` in system-wide root `PATH` profiles. Apple installer scripts and `launchd` plists expect BSD flag semantics and can break if `sed` or `tar` silently resolves to GNU variants.

## Related Scripts

- [scripts/macos/mac-headless-server.sh](../scripts/macos/mac-headless-server.sh) — Configure `pmset` for 24/7 operation, enable Remote Login (SSH), and install core Homebrew packages
- [scripts/macos/Brewfile.server](../scripts/macos/Brewfile.server) — Curated Homebrew bundle for headless ops Macs
