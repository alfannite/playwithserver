# Contributing to playwithserver

Standards, structure requirements, and validation checks for adding or updating guides and scripts.

[← Home](README.md)

## Editorial Standards

1. **Zero fluff:** Start directly with scope, navigation, and actionable commands. Do not add generic introductions or closing summaries.
2. **No decorative emojis:** Rely on Markdown headings, tables, code blocks, `> **Watch out:**` callouts, and explicit text safety tags (`[ROOT]`, `[NON-ROOT]`, `[DESTRUCTIVE]`, `[REBOOT]`).
3. **Concrete tool entries:** Never list a tool with a bare one-line description. Include the exact install command for the target OS/distro, 2–4 real-world flags or usage examples, and at least one gotcha.
4. **Modern tooling first:** Prefer `ss` over `netstat`, `ip` over `ifconfig`, `dnf` over `yum`, `nftables`/`firewalld`/`ufw` over raw legacy `iptables` where applicable, `Get-NetTCPConnection` over `netstat.exe`, `scutil`/`networksetup` on macOS, and `launchctl bootstrap`/`bootout` over deprecated `launchctl load`/`unload`. Mention legacy commands only when required for older enterprise systems.
5. **No placeholders:** Do not submit `TODO`, `TBD`, or stub sections.

## Five-File Variant Convention

Every `<platform>/<variant>/` directory must include all five files:

| File | Required Content |
| --- | --- |
| `01-bootstrap.md` | First-boot setup, repositories, base packages, time sync, guest agents/drivers |
| `02-tools.md` | Categorized tool matrix + copy-paste commands with high-value flags and gotchas |
| `03-tips-tricks.md` | Non-obvious sysadmin tricks, kernel/OS tuning, shortcuts, OS quirks |
| `04-hardening.md` | Production-safe security baselines that do not break Docker, Kubernetes, or networking |
| `05-troubleshooting.md` | Symptom -> Diagnostic Command -> Fix matrix + diagnostic one-liners |

## Guide File Template

Every Markdown guide must follow this layout:

```markdown
# <Clear Technical Title>

One-sentence scope describing what this guide covers and on which systems.

[← Back to <Platform>](../README.md) | [Home](../../README.md)

## Contents
(Include when the document has more than 4 H2 sections)

## Section Heading

`[ROOT]`
```bash
# Exact, tested command
```

> **Watch out:** Concrete failure mode or production edge case.
```

## Script Standards

- **Bash scripts (`.sh`):** Must begin with `#!/usr/bin/env bash`, enforce `set -euo pipefail`, provide a usage header (`--help`), validate arguments and privileges before mutating state, and carry executable permissions (`chmod +x` / git mode `100755`).
- **PowerShell scripts (`.ps1`):** Must include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`), `#Requires` statements where appropriate, `$ErrorActionPreference = 'Stop'`, and explicit `-WhatIf` or confirmation safeguards for destructive steps.
- Register every new script in [scripts/README.md](scripts/README.md) with target OS, safety tags, and usage examples.

## Pre-PR Verification Checklist

Run these checks locally before opening a pull request:

```bash
# 1. Validate Bash script syntax
find scripts -name '*.sh' -exec bash -n {} +

# 2. Check for leftover placeholders
grep -rnE '\b(TODO|TBD)\b|add more here|similar to above' . --exclude-dir=.git --exclude=CONTRIBUTING.md

# 3. Verify executable bit on shell scripts in git index
git ls-files --stage scripts/ | grep '\.sh$'
```

> **Watch out:** Always test hardening changes in a disposable VM or with a second open SSH session before submitting them. Hardening rules that silently drop container bridge traffic (`docker0`, `cni0`, `flannel.1`) or lock out non-root SSH administrators will be rejected.
