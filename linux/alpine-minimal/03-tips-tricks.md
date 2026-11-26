# Alpine Linux Tips and Tricks

Practical workflows for `/etc/apk/world`, `@testing` repository pinning, `musl` libc quirks, BusyBox vs GNU traps, OpenRC tuning, `lbu` diskless workflows, and clean release upgrades.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Declarative Package Management with `/etc/apk/world`](#declarative-package-management-with-etcapkworld)
- [Pinning `edge/testing` Packages Safely](#pinning-edgetesting-packages-safely)
- [`musl` libc Quirks and Workarounds](#musl-libc-quirks-and-workarounds)
- [BusyBox Ash and Coreutils Flag Differences](#busybox-ash-and-coreutils-flag-differences)
- [OpenRC Tuning and Service Supervision](#openrc-tuning-and-service-supervision)
- [Diskless Mode (`lbu`) Best Practices](#diskless-mode-lbu-best-practices)
- [In-Place Major Release Upgrades](#in-place-major-release-upgrades)

## Declarative Package Management with `/etc/apk/world`

Every explicitly installed package is recorded as a single line in `/etc/apk/world`. Removing a package from the world file and running `apk fix` converges the host declaratively—ideal for immutable configs and Ansible/Terraform provisioning.

```sh
# [NON-ROOT] Inspect explicitly requested packages
cat /etc/apk/world

# [ROOT] Install a package with a version constraint directly in world
apk add 'nginx<1.28'

# [ROOT] Clean up dependencies after manually editing /etc/apk/world
apk fix

# [ROOT] Verify local APK cache usage and purge unused archives
apk cache clean
```

### Container Multi-Stage and Virtual Package Pattern

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata \
 && apk add --no-cache --virtual .build-deps gcc musl-dev make \
 && make -C /src install \
 && apk del .build-deps
```

## Pinning `edge/testing` Packages Safely

Tag edge repositories in `/etc/apk/repositories` so `apk` pulls from them **only** when explicitly requested with `@tag`.

```sh
# [ROOT] Add tagged edge repositories at the bottom of /etc/apk/repositories
cat <<'EOF' >> /etc/apk/repositories
@edge https://dl-cdn.alpinelinux.org/alpine/edge/community
@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

apk update

# [ROOT] Install a single package from @testing while keeping the rest of the OS on stable
apk add some-new-cli@testing
```

> **Watch out:** If a `@testing` package depends on a newer `musl` or `libssl` ABI only present in `edge/main`, `apk` will refuse to satisfy constraints or pull `edge` libraries if `@edge` is untagged. Prefer standalone Go/Rust static tools from `@testing` rather than C++ libraries tightly coupled to `edge/main`.

## `musl` libc Quirks and Workarounds

Alpine links against `musl` rather than GNU `glibc`. Production outages on Alpine containers and VMs frequently stem from four concrete behavioral differences:

| Area | `glibc` Behavior | `musl` Behavior | Operational Fix |
| :--- | :--- | :--- | :--- |
| DNS queries | Sequential failover across `nameserver` lines in `/etc/resolv.conf` | Queries all `nameserver` entries in parallel and uses the first response (even `NXDOMAIN` from a split-horizon server) | Point `/etc/resolv.conf` at a single local resolver (`unbound`/`dnsmasq`/CoreDNS) rather than mixing internal + public resolvers |
| DNS `search` / `ndots` | Respects `options ndots:N`, `timeout`, `attempts` | Supports `search` and `ndots` (v1.2.4+ supports TCP fallback), but ignores `single-request` and `rotate`; watch Kubernetes `ndots:5` multiplying queries | Use trailing dots (`api.internal.`) or tune pod `dnsConfig.options` (`ndots:2`) |
| Default thread stack size | 8 MB (`ulimit -s`) | **128 KB** default per pthread | Deep recursion in Python, Ruby, Rust, or C++ apps hits SIGSEGV; increase stack size in runtime (`RUBY_THREAD_VM_STACK_SIZE`, `RUST_MIN_STACK`, `pthread_attr_setstacksize`) |
| Prebuilt glibc binaries | Runs natively | Fails with `sh: ./app: not found` (missing `/lib64/ld-linux-x86-64.so.2`) | Prefer musl-compiled/static binaries; if forced to run a closed-source glibc binary, install `gcompat` |
| Timezones & Locales | Bundled in `glibc`/`locales` | No zoneinfo or non-UTF8 locales by default | `apk add tzdata` for `TZ=...`; `apk add musl-locales` if localized formatting is required |

```sh
# [ROOT] Compatibility shim for simple closed-source glibc binaries (last resort)
apk add gcompat libstdc++
```

> **Watch out:** `gcompat` is a thin compatibility shim, not full `glibc`. Complex proprietary agents (some APM tracers, JVM JNI native libs, or CUDA/ML wheels) can still crash under `gcompat`. For Python ML workloads or heavy glibc ecosystems, use a Debian Slim base image instead of fighting `musl`.

## BusyBox Ash and Coreutils Flag Differences

Alpine uses BusyBox for `/bin/sh` (`ash`), `ps`, `grep`, `sed`, `tar`, `find`, and `wget`. Scripts written for Bash + GNU coreutils break on missing flags.

| Command | GNU / Bash Expectation | BusyBox Behavior | Fix |
| :--- | :--- | :--- | :--- |
| `/bin/sh` | `[[ ]]`, arrays, `set -o pipefail` | POSIX `ash` (supports `pipefail` in recent BusyBox, no bash arrays) | Write POSIX sh or `apk add bash` |
| `grep -P` | Perl regex (`-P`) | Unsupported | `apk add grep` or use `grep -E` |
| `tar --zstd` | Built-in zstd decompression | Unsupported | `apk add tar zstd` |
| `ps auxf` | Process forest with GNU flags | Ignores BSD/GNU flags (`ps -o pid,ppid,user,args`) | `apk add procps-ng` |
| `wget` | TLS flags, `--retry-connrefused` | Minimal applet | `apk add curl` or `apk add wget` |
| `date -d` | Flexible natural-language parsing | Strict ISO/epoch formats only | `apk add coreutils` |

## OpenRC Tuning and Service Supervision

### Parallel Boot and Per-Service Configuration `[ROOT]`

Every OpenRC service reads environment overrides from `/etc/conf.d/<service>` rather than editing `/etc/init.d/<service>` directly (which gets overwritten on upgrades).

```sh
# [ROOT] Enable parallel service startup and boot logging in /etc/rc.conf
sed -i \
  -e 's/^#rc_parallel="NO"/rc_parallel="YES"/' \
  -e 's/^#rc_logger="NO"/rc_logger="YES"/' \
  /etc/rc.conf
```

### Automatic Crash Restart with `supervise-daemon` `[ROOT]`

OpenRC does not auto-restart crashed daemons unless the init script uses `supervisor="supervise-daemon"`. Add supervision cleanly via `/etc/conf.d/<service>`:

```sh
# [ROOT] Example: enable automatic restart for a service in /etc/conf.d/caddy
cat <<'EOF' >> /etc/conf.d/caddy
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=10
respawn_period=60
EOF

rc-service caddy restart
```

## Diskless Mode (`lbu`) Best Practices

```sh
# [ROOT] Keep up to 3 historical .apkovl backups on media for instant rollback
sed -i 's/^#BACKUP_LIMIT=.*/BACKUP_LIMIT=3/' /etc/lbu/lbu.conf

# [ROOT] Exclude volatile cache/socket paths accidentally included under /etc
lbu exclude /etc/resolv.conf

# [ROOT] Check size of the overlay archive (keep it under a few MB for fast boot)
ls -lh /media/*/*.apkovl.tar.gz
```

## In-Place Major Release Upgrades

Upgrading a `sys` install between stable Alpine releases (e.g., `v3.20` to `v3.21`):

```sh
# [ROOT] [REBOOT] 1. Update release version in /etc/apk/repositories
sed -i 's/v3\.20/v3.21/g' /etc/apk/repositories

# 2. Refresh index and upgrade all packages (including architecture/ABI shifts)
apk update
apk upgrade --available

# 3. Review any .apk-new configuration files created during upgrade
find /etc -name '*.apk-new'

# 4. Sync and reboot into the new kernel
sync && reboot
```
