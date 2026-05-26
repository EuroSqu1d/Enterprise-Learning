# Monitoring Stack

Prometheus + Grafana + Node Exporter + cAdvisor in a single compose stack.

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | `9090` | Time-series DB; scrapes metrics every 15s, 30d retention |
| Grafana | `3000` | Dashboards; Prometheus pre-wired as the default datasource |
| Node Exporter | `9100` | Host metrics (CPU, RAM, disk, network) |
| cAdvisor | `8080` | Per-container CPU/RAM/network metrics |

## Prerequisites

Docker Engine + Compose plugin — see `../docker/`.

## Run

```bash
cp .env.example .env
# edit .env and set GF_SECURITY_ADMIN_PASSWORD to something real
docker compose up -d
docker compose ps
```

Then browse:
- Grafana: `http://<host>:3000` — login with the credentials from `.env`
- Prometheus: `http://<host>:9090` → *Status → Targets* should show all 3 jobs UP
- cAdvisor UI: `http://<host>:8080`

## Add dashboards

Two options:

**A. UI import (fastest)** — In Grafana go to *Dashboards → New → Import*, enter a dashboard ID from grafana.com, pick Prometheus as the datasource. Good starting IDs:

| ID | Dashboard |
|----|-----------|
| `1860` | Node Exporter Full |
| `14282` | cAdvisor — Docker monitoring |
| `3662` | Prometheus 2.0 Overview |

**B. Provisioned (version-controlled)** — drop the dashboard JSON in `grafana/dashboards/`. The provider in `grafana/provisioning/dashboards/dashboards.yml` polls that folder every 30s and auto-loads anything new. To grab a dashboard JSON:

```bash
curl -fsSL https://grafana.com/api/dashboards/1860/revisions/latest/download \
  -o grafana/dashboards/node-exporter-full.json
docker compose restart grafana   # only needed first time
```

## Update

```bash
docker compose pull
docker compose up -d
```

## Stop / clean up

```bash
docker compose down            # stop, keep data
docker compose down -v         # stop AND delete prometheus + grafana volumes
```

## Notes

- All services run on a named `monitoring` docker network so Prometheus can scrape `node-exporter:9100` and `cadvisor:8080` by service name.
- Prometheus storage path is on the named volume `prometheus-data`. Grafana DB + plugins live in `grafana-data`. Back these up if you care about long-term history.
- cAdvisor needs `privileged: true` and a `/dev/kmsg` device to read container stats — that's standard, not paranoia.
- Node Exporter mounts the host `/proc`, `/sys`, and `/` read-only. Filesystem metrics for container overlays are excluded via `--collector.filesystem.mount-points-exclude`.
