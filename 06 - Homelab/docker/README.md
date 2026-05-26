# Docker Engine

Install Docker Engine + Compose plugin on Ubuntu/Debian from Docker's official apt repository.

## Install

```bash
sudo ./install.sh
```

The script is idempotent — safe to re-run.

## Post-install

Add your user to the `docker` group so you can run `docker` without sudo:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
docker run --rm hello-world
```

## Verify

```bash
docker --version
docker compose version
```
