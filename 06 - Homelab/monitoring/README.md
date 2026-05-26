# Monitoring Stack

Metrics (Prometheus + exporters) and logs (Loki + Promtail) in one compose stack, both visualised in Grafana.

| Service | Image | Host port | Purpose |
|---------|-------|-----------|---------|
| Prometheus | `prom/prometheus:v2.54.1` | `9090` | Metrics TSDB, 30d retention |
| Node Exporter | `prom/node-exporter:v1.8.2` | `9100` | Host metrics |
| cAdvisor | `gcr.io/cadvisor/cadvisor:v0.49.1` | `8080` | Per-container metrics |
| Loki | `grafana/loki:3.1.1` | *not exposed* | Log storage |
| Promtail | `grafana/promtail:3.1.1` | *not exposed* | Log shipper (host + container logs) |
| Grafana | `grafana/grafana-oss:11.2.0` | `3000` | Dashboards, Prometheus + Loki pre-wired |

All image tags are pinned. See the comments in `docker-compose.yml` for the bump procedure.

## Prerequisites

1. Docker Engine + Compose plugin — see `../docker/`.
2. **`/etc/docker/daemon.json` must include the `tag` log-opt** (the docker installer in `../docker/install.sh` writes this for you). Without it, Promtail can only label container logs by ID instead of `image/name/id`.

## Run

```bash
cp .env.example .env
# edit .env and set GF_SECURITY_ADMIN_PASSWORD to something real
docker compose up -d
docker compose ps
```

Then:
- **Grafana**: `http://<host>:3000` — login with the creds from `.env`. Both *Prometheus* and *Loki* appear under *Connections → Data sources*, pre-wired.
- **Prometheus**: `http://<host>:9090` → *Status → Targets* — all 5 jobs should be `UP`.
- **cAdvisor**: `http://<host>:8080` (raw UI).
- **Loki**: not exposed to the host on purpose. Query it via Grafana → *Explore* → select Loki datasource → try `{job="docker"}`.

## Querying logs (LogQL)

Examples to drop into Grafana → Explore → Loki:

```logql
# All logs from a specific container
{container="grafana"}

# All host syslog lines containing "failed"
{job="varlogs"} |= "failed"

# Errors across every container in the last 5 minutes
{job="docker"} |~ "(?i)error|warn"

# Rate of log lines per container (panel/graph)
sum by (container) (rate({job="docker"}[1m]))
```

## Add metric dashboards

Two options:

**A. UI import** — In Grafana → *Dashboards → New → Import*, enter an ID:

| ID | Dashboard |
|----|-----------|
| `1860` | Node Exporter Full |
| `14282` | cAdvisor — Docker monitoring |
| `3662` | Prometheus 2.0 Overview |
| `13639` | Loki logs/metrics |

**B. Provisioned (version-controlled)** — drop the JSON in `grafana/dashboards/`. The provider in `grafana/provisioning/dashboards/dashboards.yml` polls that folder every 30s and auto-loads anything new:

```bash
curl -fsSL https://grafana.com/api/dashboards/1860/revisions/latest/download \
  -o grafana/dashboards/node-exporter-full.json
```

## Security posture (Loki + Promtail)

These mitigations are baked into the configs — listed here so you know *why* the files look the way they do:

| Mitigation | Where |
|------------|-------|
| Pinned image tags (no `:latest`) | `docker-compose.yml` |
| Loki not exposed to host network | no `ports:` block on `loki` service |
| No `/var/run/docker.sock` mount on Promtail | `promtail` `volumes:` |
| All Promtail host mounts read-only | `:ro` on every mount |
| Secret pattern scrubbing before ingest | `promtail/promtail-config.yaml` → `replace` pipeline stages |
| Grafana sign-up disabled | `GF_USERS_ALLOW_SIGN_UP=false` |
| Grafana admin password fails-loud if unset | `GF_SECURITY_ADMIN_PASSWORD:?` |
| Datasources locked in UI (provisioning is source of truth) | `editable: false` |

The trade-off you accepted by skipping the docker socket: Promtail discovers containers by file path. Container *names* still appear as labels, but only because the docker daemon tags each log line via the `tag` log-opt in `daemon.json`. If you ever revert that, container logs will be labelled by ID only.

## Update

```bash
# Bump tags in docker-compose.yml first.
docker compose pull
docker compose up -d
```

## Stop / clean up

```bash
docker compose down            # stop, keep data
docker compose down -v         # ALSO delete prometheus/grafana/loki volumes
```

## Notes

- All services run on a named `monitoring` docker network so Prometheus can scrape exporters by service name and Grafana can reach Prometheus/Loki by service name.
- Loki uses filesystem storage in the `loki-data` volume. For homelab volumes it's fine; if you ever push GB/day, consider S3-compatible object storage (MinIO etc.).
- Promtail's read position is persisted in `promtail-positions`, so a restart doesn't re-ship every existing log file.
