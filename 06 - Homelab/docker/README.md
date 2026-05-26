# Docker Engine

Install Docker Engine + Compose plugin on Ubuntu/Debian from Docker's official apt repository.

## Files

| File | Purpose |
|------|---------|
| `install.sh` | Installs Docker Engine, CLI, containerd, buildx, compose plugin. Writes `/etc/docker/daemon.json` with log-rotation defaults. Idempotent. |
| `post-install.sh` | Adds your user to the `docker` group so you can run docker without sudo. |
| `daemon.json` | Reference copy of the daemon config the installer drops at `/etc/docker/daemon.json`. |

## Install

```bash
sudo ./install.sh
./post-install.sh
# log out and back in (or: newgrp docker)
docker run --rm hello-world
```

## What `install.sh` does

1. Verifies Ubuntu/Debian and reads the codename from `/etc/os-release`.
2. Removes legacy/conflicting packages (`docker.io`, `podman-docker`, old `containerd`, etc.).
3. Adds Docker's official GPG key and apt repository.
4. Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
5. Writes `/etc/docker/daemon.json` (10MB log files, 3 rotations) — only if you don't already have one.
6. Enables + restarts the `docker` systemd unit.

## Verify

```bash
docker --version
docker compose version
docker info | grep -i 'logging driver'
```
