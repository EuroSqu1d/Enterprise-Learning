# Homelab

Installation scripts, compose stacks, and configuration for the services running in the homelab.

## Why one repo

Single repo, one subdirectory per service (or per tightly-coupled stack). Easier to clone, search across, and share config (networks, secrets, reverse-proxy routes) between stacks. Split a service into its own repo only if it outgrows this layout.

## Structure

| Folder | What | Purpose |
|--------|------|---------|
| `docker/` | Host install | Docker Engine + Compose plugin install scripts |
| `monitoring/` | Compose stack | Prometheus + Grafana + Node Exporter + cAdvisor |

## Conventions

- Each service folder has its own `README.md` with install/run steps.
- Host-level installers live as shell scripts (`install.sh`, `post-install.sh`).
- Containerised stacks ship a `docker-compose.yml` and a `.env.example`. The real `.env` is gitignored.
- Tightly-coupled services live in a single stack folder (e.g. `monitoring/`). Independent services get their own folder.

## Order of install

1. `docker/` — install Docker on the host
2. `monitoring/` — bring up the metrics stack
3. (next services go here)

## Target host

Ubuntu/Debian on the hypervisors and VMs listed in the root `README.md`.
