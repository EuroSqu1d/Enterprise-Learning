#!/usr/bin/env bash
# Post-install: add the invoking user to the docker group so they can run
# docker without sudo. Run as your normal user (NOT root).
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not root." >&2
  exit 1
fi

target="${SUDO_USER:-$USER}"

if ! getent group docker >/dev/null; then
  echo "docker group does not exist — install Docker first (sudo ./install.sh)" >&2
  exit 1
fi

if id -nG "$target" | tr ' ' '\n' | grep -qx docker; then
  echo "User '$target' is already in the docker group."
else
  echo ">>> Adding $target to the docker group (needs sudo)"
  sudo usermod -aG docker "$target"
  echo
  echo "Group membership added. You must log out and back in (or run 'newgrp docker')"
  echo "before docker commands work without sudo."
fi

echo
echo "Test with:  docker run --rm hello-world"
