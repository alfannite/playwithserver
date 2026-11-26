# Alpine Linux Troubleshooting

Symptom-to-fix matrix and recovery playbooks for `musl` DNS/stack/binary issues, `apk` constraint errors, OpenRC crashed services, BusyBox script traps, and `lbu` diskless persistence on Alpine Linux.

[← Back to Linux](../README.md) | [Home](../../README.md)

## Contents

- [Symptom-to-Fix Matrix](#symptom-to-fix-matrix)
- [Diagnosing `musl` DNS, Stack, and Binary Failures](#diagnosing-musl-dns-stack-and-binary-failures)
- [Recovering OpenRC Crashed and Stuck Services](#recovering-openrc-crashed-and-stuck-services)
- [Fixing `apk` World Conflicts and Broken Repositories](#fixing-apk-world-conflicts-and-broken-repositories)
- [Diskless Mode (`lbu`) Recovery](#diskless-mode-lbu-recovery)
- [High-Signal Diagnostic One-Liners](#high-signal-diagnostic-one-liners)

## Symptom-to-Fix Matrix

| Symptom | Diagnostic Command | Root Cause / Fix |
| :--- | :--- | :--- |
| `sh: ./binary: not found` even though file exists and is `+x` | `file ./binary; ldd ./binary` | Binary is dynamically linked against `glibc` (`/lib64/ld-linux-x86-64.so.2`). Recompile statically/for `musl` or `apk add gcompat`. |
| Intermittent `NXDOMAIN` or internal hostname failures | `cat /etc/resolv.conf; getent ahosts host.internal` | `musl` queries all `nameserver` entries in parallel and accepts the first `NXDOMAIN`. Use a single forwarding resolver instead of mixing internal + `8.8.8.8`. |
| App crashes with `SIGSEGV` inside deep recursion / worker threads | `dmesg \| tail; strace -f <cmd>` | `musl` defaults to 128 KB thread stack (vs 8 MB on `glibc`). Increase runtime stack env var (`RUST_MIN_STACK`, `RUBY_THREAD_VM_STACK_SIZE`, etc.). |
| `apk add` fails with `ERROR: unable to select packages` | `cat /etc/apk/repositories` | `community` repo commented out or version mismatch. Uncomment `community` and run `apk update`. |
| `apk` reports `world` unsatisfiable constraints | `cat /etc/apk/world; apk fix -s` | Stale pinned version or removed package in `/etc/apk/world`. Remove offending entry from `/etc/apk/world` and run `apk fix`. |
| `rc-service <svc> start` says `WARNING: <svc> has already been started` (or `crashed`) | `rc-status --crashed; tail -n 50 /var/log/messages` | Daemon died without OpenRC cleanup. Run `rc-service <svc> zap && rc-service <svc> start`. |
| Config changes or users vanish after reboot | `mount \| grep ' / '; lbu status` | Host runs in `diskless` (`tmpfs`) mode without `lbu commit`. Add paths via `lbu include` and run `lbu commit -d`. |
| `TZ=America/New_York` ignored (timestamps stay UTC) | `ls /usr/share/zoneinfo` | `tzdata` not installed. Run `apk add --no-cache tzdata`. |
| `doas: Operation not permitted` or syntax rejection | `doas -C /etc/doas.d/*.conf` | Missing trailing newline, wrong group membership (`id`), or bad permissions. Fix from root console. |

## Diagnosing `musl` DNS, Stack, and Binary Failures

### 1. Dynamic Linker / glibc Mismatch `[NON-ROOT]`

```sh
# [NON-ROOT] Inspect ELF interpreter of an executable that reports "not found"
readelf -l ./myapp 2>/dev/null | grep interpreter
# Expected on Alpine: /lib/ld-musl-x86_64.so.1
# If it shows /lib64/ld-linux-x86-64.so.2, it requires glibc or static build

# Inspect missing shared libraries
ldd ./myapp
```

### 2. Reproducing `musl` DNS Resolution `[NON-ROOT]`

```sh
# [NON-ROOT] Test exact musl getaddrinfo() resolution (unlike drill/dig which bypass musl)
getent ahosts internal-db.corp.local

# Inspect active nameservers and search/ndots options
cat /etc/resolv.conf

# Capture real-time DNS queries to verify parallel NXDOMAIN races
doas tcpdump -i any -nn -vv port 53
```

> **Watch out:** In Kubernetes clusters with Alpine pods, `ndots:5` combined with `search` domains causes `musl` to fire parallel `A` + `AAAA` queries for every search domain suffix on short external names. Add trailing dots to external FQDNs or configure `ndots:2` in the pod spec to cut CoreDNS load dramatically.

## Recovering OpenRC Crashed and Stuck Services

```sh
# [NON-ROOT] List all services in crashed or stopped state
rc-status --crashed

# [ROOT] Check boot log and syslog for startup errors
tail -n 100 /var/log/rc.log
tail -n 100 /var/log/messages

# [ROOT] Reset a crashed service's state file and start cleanly
rc-service nginx zap
rc-service nginx start

# [ROOT] Trace an OpenRC init script line-by-line when a daemon silently fails to start
rc-service --debug nginx start
```

### Checking Service Dependencies `[NON-ROOT]`

```sh
# [NON-ROOT] Inspect dependency tree for a failing service
rc-service nginx describe
grep -E 'need |use |after ' /etc/init.d/nginx
```

## Fixing `apk` World Conflicts and Broken Repositories

```sh
# [ROOT] Simulate apk fix without modifying the system
apk fix --simulate

# [ROOT] Force refresh of corrupted APKINDEX cache
rm -rf /var/cache/apk/*
apk update

# [ROOT] Inspect which package pulls in a conflicting dependency
apk info --rdepends openssl

# [ROOT] Check for broken symlinks or missing shared objects across all installed packages
apk audit --system
```

> **Watch out:** Never delete `/lib/apk/db/installed` or `/etc/apk/world` to "clear" an error. `/lib/apk/db/installed` is the sole database of installed files on the system; deleting it breaks `apk` permanently and requires reinstalling every package with `apk fix --force-overwrite`.

## Diskless Mode (`lbu`) Recovery

If a bad config was committed in diskless mode and breaks networking or SSH on boot:

1. Boot the Alpine host or mount the boot media (`/media/sda1` or `/media/usb`) from another machine.
2. Inspect backup overlays (`<hostname>.apkovl.tar.gz` and numbered `.1.tar.gz` backups if `BACKUP_LIMIT` was configured).
3. Inspect or revert the overlay archive:

```sh
# [ROOT] Inspect contents of a saved overlay archive
tar -tzvf /media/sda1/edge-gw-01.apkovl.tar.gz | head -n 40

# [ROOT] Roll back to previous backup overlay (if BACKUP_LIMIT > 0)
mv /media/sda1/edge-gw-01.apkovl.tar.gz /media/sda1/edge-gw-01.apkovl.tar.gz.bad
cp /media/sda1/edge-gw-01.apkovl.1.tar.gz /media/sda1/edge-gw-01.apkovl.tar.gz
sync && reboot
```

## High-Signal Diagnostic One-Liners

```sh
# [NON-ROOT] Check Alpine release version, kernel, and architecture
cat /etc/alpine-release && uname -a

# [NON-ROOT] List top 20 largest installed packages in KiB
apk info -s $(apk info) | awk '/installed size:/{pkg=$1; getline; print $1, pkg}' | sort -nr | head -n 20

# [ROOT] Inspect listening ports and processes (requires iproute2-ss)
doas ss -tulnp

# [NON-ROOT] Check kernel OOM kills and hardware/filesystem errors
dmesg | grep -iE 'oom|killed|error|fail|readonly' | tail -n 30

# [NON-ROOT] Show remaining tmpfs RAM space on diskless systems
df -h / /run /tmp

# [NON-ROOT] Find unmerged .apk-new config files after an upgrade
find /etc -name '*.apk-new' 2>/dev/null
```
