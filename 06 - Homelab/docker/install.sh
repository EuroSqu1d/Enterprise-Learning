#!/usr/bin/env bash
# Install Docker Engine + Compose plugin on Ubuntu/Debian from Docker's official apt repo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo $0)" >&2
  exit 1
fi

. /etc/os-release
distro="${ID}"
codename="${VERSION_CODENAME}"

if [[ "$distro" != "ubuntu" && "$distro" != "debian" ]]; then
  echo "Unsupported distro: $distro (expected ubuntu or debian)" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${distro}/gpg" \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

arch="$(dpkg --print-architecture)"
echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${distro} ${codename} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker

docker --version
docker compose version

echo
echo "Done. Add your user to the docker group:"
echo "  sudo usermod -aG docker \"\$USER\" && newgrp docker"
