# Homelab

Installation scripts, compose stacks, and configuration for the services running in the homelab.

> **New to this?** Read **[GUIDE.md](./GUIDE.md)** first — it explains every piece in plain English, why the configs look the way they do, and walks you through bringing the whole stack up from a fresh server. The READMEs in each subfolder are reference docs, not tutorials.

## Why one repo

Single repo, one subdirectory per service (or per tightly-coupled stack). Easier to clone, search across, and share config (networks, secrets, reverse-proxy routes) between stacks. Split a service into its own repo only if it outgrows this layout.

## Structure

| Folder | What | Purpose |
|--------|------|---------|
| `docker/` | Host install | Docker Engine + Compose plugin install scripts |
| `monitoring/` | Compose stack | Prometheus + Grafana + Node Exporter + cAdvisor + Loki + Promtail |
| `jellyfin/` | Compose stack | Self-hosted media server (movies / TV / music) |
| `cloudflared/` | Compose stack | Cloudflare Tunnel — public HTTPS access without opening ports |

## Conventions

- Each service folder has its own `README.md` with install/run steps.
- Host-level installers live as shell scripts (`install.sh`, `post-install.sh`).
- Containerised stacks ship a `docker-compose.yml` and a `.env.example`. The real `.env` is gitignored.
- Tightly-coupled services live in a single stack folder (e.g. `monitoring/`). Independent services get their own folder.

## Order of install

1. `docker/` — install Docker on the host
2. `monitoring/` — bring up the metrics + logs stack
3. `jellyfin/` — media server
4. (next services go here)

## Target host

Ubuntu/Debian on the hypervisors and VMs listed in the root `README.md`.
