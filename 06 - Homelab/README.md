# Homelab

Installation scripts, compose stacks, and configuration for the services running in the homelab.

## Why one repo

Single repo, one subdirectory per service. Easier to clone, search across, and share config (networks, secrets, reverse-proxy routes) between stacks. Split a service into its own repo only if it outgrows this layout.

## Structure

| Folder | Service | Purpose |
|--------|---------|---------|
| `docker/` | Docker Engine | Host-level container runtime install |
| `grafana/` | Grafana | Dashboards and visualisation |

## Conventions

- Each service folder has its own `README.md` with install/run steps.
- Host-level installers live as shell scripts (`install.sh`).
- Containerised services ship a `docker-compose.yml` and a `.env.example`.
- Never commit real secrets — use `.env` (gitignored) alongside `.env.example`.

## Target host

Ubuntu/Debian on the hypervisors and VMs listed in the root `README.md`.
