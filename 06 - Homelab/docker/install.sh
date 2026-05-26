#!/usr/bin/env bash
# Install Docker Engine + Compose plugin on Ubuntu/Debian from Docker's official apt repo.
# Idempotent: safe to re-run. Configures log rotation via /etc/docker/daemon.json.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo $0)" >&2
  exit 1
fi

# --- 1. Detect distro -------------------------------------------------------
. /etc/os-release
distro="${ID:-}"
codename="${VERSION_CODENAME:-}"

if [[ "$distro" != "ubuntu" && "$distro" != "debian" ]]; then
  echo "Unsupported distro: $distro (expected ubuntu or debian)" >&2
  exit 1
fi

if [[ -z "$codename" ]]; then
  echo "Could not determine VERSION_CODENAME from /etc/os-release" >&2
  exit 1
fi

echo ">>> Installing Docker on ${distro} ${codename}"

# --- 2. Remove conflicting legacy packages ---------------------------------
echo ">>> Removing any conflicting legacy packages"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

# --- 3. Base dependencies ---------------------------------------------------
echo ">>> Installing prerequisites"
apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

# --- 4. Docker apt repo + signing key --------------------------------------
echo ">>> Configuring Docker apt repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${distro}/gpg" \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

arch="$(dpkg --print-architecture)"
echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${distro} ${codename} stable" \
  > /etc/apt/sources.list.d/docker.list

# --- 5. Install Docker Engine + plugins -----------------------------------
echo ">>> Installing Docker Engine, CLI, containerd, buildx and compose plugins"
apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# --- 6. Daemon defaults: log rotation --------------------------------------
echo ">>> Writing /etc/docker/daemon.json (log rotation defaults)"
install -m 0755 -d /etc/docker
if [[ ! -f /etc/docker/daemon.json ]]; then
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
else
  echo "    daemon.json already exists — leaving it alone"
fi

# --- 7. Enable + start ------------------------------------------------------
systemctl enable --now docker
systemctl restart docker

# --- 8. Report --------------------------------------------------------------
echo
echo ">>> Done."
docker --version
docker compose version
echo
echo "Next: run ./post-install.sh as your unprivileged user to enable rootless usage."
