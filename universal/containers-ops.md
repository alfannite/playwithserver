# Containers Operations (Docker & Podman)

Production container inspection one-liners, log rotation, safe disk reclamation, rootless Podman/Docker mechanics, and Compose healthchecks.

[← Home](../README.md)

## Contents

- [Docker vs Podman Operational Map](#docker-vs-podman-operational-map)
- [High-Signal Inspect and Format One-Liners](#high-signal-inspect-and-format-one-liners)
- [Log Rotation and Daemon Baseline](#log-rotation-and-daemon-baseline)
- [Safe Prune and Disk Reclamation](#safe-prune-and-disk-reclamation)
- [Rootless Containers and Quadlet Systemd Units](#rootless-containers-and-quadlet-systemd-units)
- [Production Compose Healthchecks and Resource Limits](#production-compose-healthchecks-and-resource-limits)
- [Container Troubleshooting Matrix](#container-troubleshooting-matrix)

## Docker vs Podman Operational Map

| Concept | Docker Engine | Podman |
| --- | --- | --- |
| Architecture | Root `dockerd` daemon (or rootless daemon) | Daemonless fork/exec per container (`conmon`) |
| Rootless support | Optional (`dockerd-rootless-setuptool.sh`) | First-class default for unprivileged users |
| Systemd integration | `restart: unless-stopped` managed by `dockerd` | Native Quadlet `.container` unit files in `~/.config/containers/systemd/` |
| Compose CLI | `docker compose` (v2 plugin) | `podman compose` (delegates to `podman-compose` or `docker-compose`) |
| API socket | `/var/run/docker.sock` | `$XDG_RUNTIME_DIR/podman/podman.sock` (`systemctl --user enable --now podman.socket`) |
| SELinux volume label | `:Z` (private) or `:z` (shared) | `:Z` or `:z` required on enforcing RHEL/Fedora/MicroOS hosts |

## High-Signal Inspect and Format One-Liners

Every `docker` command below works identically with `podman` by replacing the binary name.

`[NON-ROOT]` (assuming user is in `docker` group or running rootless Podman)
```bash
# Compact running container table with IP, ports, and status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Print every running container's name and attached network IPs
docker inspect -f '{{.Name}} -> {{range $k,$v := .NetworkSettings.Networks}}[{{$k}}:{{$v.IPAddress}}] {{end}}' $(docker ps -q)

# Inspect exact restart count, exit code, and OOMKilled flag
docker inspect -f '{{.Name}} state={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}' $(docker ps -aq)

# Check healthcheck status and last failure output
docker inspect -f '{{json .State.Health}}' my-app | jq .

# Show container disk usage breakdown (images, containers, local volumes, build cache)
docker system df -v

# Live CPU, memory, network, and block I/O without streaming redraw (great for scripts)
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}'

# Find which container owns a host PID (Linux)
cat /proc/<PID>/cgroup
```

## Log Rotation and Daemon Baseline

By default, Docker's `json-file` logging driver has **no size limit**—a noisy service can fill `/` to 100% and crash the host. Configure global log rotation in `/etc/docker/daemon.json` immediately on every Docker host.

`[ROOT]`
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "25m",
    "max-file": "5",
    "compress": "true"
  },
  "live-restore": true,
  "default-address-pools": [
    {
      "base": "172.24.0.0/14",
      "size": 24
    }
  ]
}
```

`[ROOT]`
```bash
# Apply daemon.json cleanly (live-restore keeps running containers alive during reload/restart)
sudo systemctl reload docker || sudo systemctl restart docker

# Verify active log driver on newly created containers
docker info --format '{{.LoggingDriver}}'

# Truncate an already-huge container log file without restarting the container
sudo truncate -s 0 "$(docker inspect --format='{{.LogPath}}' my-noisy-container)"
```

> **Watch out:** Changing `log-driver` or `log-opts` in `/etc/docker/daemon.json` only applies to **newly created** containers. Existing containers retain their original logging config until recreated (`docker compose up -d --force-recreate`). Also set `default-address-pools` to prevent Docker's default `172.17.0.0/16`–`172.31.0.0/16` bridges from colliding with corporate VPN or LAN subnets.

## Safe Prune and Disk Reclamation

`[NON-ROOT]` / `[DESTRUCTIVE]`
```bash
# SAFE: remove only dangling (untagged) images and stopped containers older than 7 days
docker container prune --filter "until=168h" -f
docker image prune -f
docker builder prune --filter "until=168h" -f

# SAFE: remove unused images not referenced by any container for >30 days
docker image prune -a --filter "until=720h"

# DANGEROUS: NEVER run 'docker system prune --volumes' blindly in production
# Always list dangling volumes first and verify none hold stopped DB data:
docker volume ls -f dangling=true
```

> **Watch out:** `docker system prune -a --volumes` deletes every volume attached to a **currently stopped** container—including a database container paused for maintenance. Always inspect `docker volume ls -f dangling=true` before removing volumes.

## Rootless Containers and Quadlet Systemd Units

On RHEL 9, Fedora, Debian 12+, and openSUSE MicroOS, Podman Quadlets turn declarative INI files into native `systemd` services without maintaining brittle shell wrappers.

`[NON-ROOT]`
```bash
# Allow rootless user services to start at boot and survive SSH logout
loginctl enable-linger "$USER"

# Create a Quadlet container definition
mkdir -p ~/.config/containers/systemd
cat <<'EOF' > ~/.config/containers/systemd/caddy.container
[Unit]
Description=Caddy Reverse Proxy
After=network-online.target

[Container]
Image=docker.io/library/caddy:2-alpine
AutoUpdate=registry
PublishPort=8080:80
PublishPort=8443:443
Volume=%h/caddy/Caddyfile:/etc/caddy/Caddyfile:ro,Z
Volume=caddy_data:/data:Z

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
EOF

# Generate and start the systemd service
systemctl --user daemon-reload
systemctl --user start caddy.service
systemctl --user status caddy.service
```

Allow unprivileged rootless containers to bind ports 80/443 if needed:

`[ROOT]`
```bash
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rootless-ports.conf
sudo sysctl --system
```

## Production Compose Healthchecks and Resource Limits

Always pair `depends_on: condition: service_healthy` with explicit memory ceilings and read-only root filesystems where possible.

```yaml
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_DB: appdb
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d appdb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: "1.5"

  api:
    image: ghcr.io/org/api:1.4.2
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=64m
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "127.0.0.1:8080:8080"

volumes:
  pgdata:
```

> **Watch out:** Binding `ports: ["8080:8080"]` in Docker binds to `0.0.0.0:8080` and inserts `PREROUTING`/`DOCKER` netfilter rules that **bypass `ufw` INPUT rules**. Always bind internal services explicitly to `127.0.0.1:8080:8080` behind a reverse proxy or VPN interface.

## Container Troubleshooting Matrix

| Symptom | Diagnostic Command | Cause & Fix |
| --- | --- | --- |
| Container exits with code `137` | `docker inspect -f '{{.State.OOMKilled}}' <c>` | Killed by kernel OOM killer (`true`) or SIGKILL on shutdown timeout (`false`); raise memory limit or add `stop_grace_period` |
| `Permission denied` on bind mount (RHEL/Fedora) | `ausearch -m avc -ts recent` | SELinux blocks container access; append `:Z` (private) or `:z` (shared) to volume mount |
| `Permission denied` on bind mount (rootless) | `podman unshare ls -ln /host/path` | Host directory owned by wrong subordinate UID; fix with `podman unshare chown -R <uid>:<gid> /host/path` |
| DNS fails inside containers, works on host | `docker exec <c> cat /etc/resolv.conf` | Host uses `127.0.0.53` stub or firewall blocks bridge subnet (`docker0`/`podman0`) to port 53 |
| `no space left on device` with free `df -h` | `df -ih` and `docker system df` | Inode exhaustion on overlay2 or unrotated JSON logs; prune stopped containers/images and configure `max-size` |
| Container cannot resolve sibling by name | `docker inspect <c> --format '{{json .NetworkSettings.Networks}}'` | Attached to default `bridge` network (no embedded DNS); use a user-defined bridge network |
