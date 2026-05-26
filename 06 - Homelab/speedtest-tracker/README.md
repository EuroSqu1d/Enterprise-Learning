# Speedtest Tracker

Runs Ookla speedtest on a schedule, stores results in SQLite, and exposes the data via web UI + Prometheus metrics. Long-running tool for catching ISP issues that only become visible over weeks of data.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `ghcr.io/alexjustesen/speedtest-tracker:v0.21.2` | `8765` | Web UI + API + Prometheus metrics |

## Prerequisites

- Docker + Compose — see `../docker/`.
- The `monitoring/` stack running — optional, but the real value comes from feeding results into Grafana alongside everything else.

## Setup

### 1. Generate the app key

Laravel apps require a unique encryption key. Generate once:

```bash
docker run --rm ghcr.io/alexjustesen/speedtest-tracker:v0.21.2 \
  php artisan key:generate --show
```

Output looks like `base64:fL9...==`. Copy the whole string (including the `base64:` prefix).

### 2. Configure and start

```bash
cp .env.example .env
nano .env       # paste the APP_KEY, set TZ
docker compose up -d
docker compose logs -f speedtest-tracker
```

First start runs DB migrations (~30s). Wait for `Ready to handle connections`.

### 3. Trigger the first test

Browse to `http://<host>:8765`. First load asks you to create an admin user. Once in, click **Run new test** to verify Ookla works through your network.

The scheduled tests then run automatically per `SPEEDTEST_SCHEDULE`.

### 4. Wire into Prometheus

Add this scrape job to `../monitoring/prometheus/prometheus.yml`:

```yaml
  - job_name: speedtest
    metrics_path: /api/metrics/prometheus
    static_configs:
      - targets: ['<homelab-host>:8765']
        labels:
          host: homelab
```

Reload Prometheus:

```bash
curl -X POST http://localhost:9090/-/reload
```

Confirm in Prometheus → *Status → Targets* that `speedtest` shows `UP`.

### 5. Add a Grafana dashboard

In Grafana → **Dashboards → New → Import** → enter ID `19612` (the official Speedtest Tracker dashboard for Prometheus), pick your Prometheus datasource → Import.

You'll see panels for download/upload/ping/jitter over time, sliced by Ookla server and ISP.

## Metrics exposed

The Prometheus endpoint serves at `http://<host>:8765/api/metrics/prometheus`. Useful series:

| Metric | What it is |
|--------|------------|
| `speedtest_download_bits_per_second` | Last download speed |
| `speedtest_upload_bits_per_second` | Last upload speed |
| `speedtest_ping_ms` | Last ping latency |
| `speedtest_jitter_ms` | Last jitter |
| `speedtest_packet_loss` | Last packet loss percent |

These are gauges that update on each scheduled test, so set Grafana panels to display the latest value, not rates.

## Alerts (optional)

Add to `../monitoring/prometheus/rules/alerts.yml`:

```yaml
  - name: speedtest
    rules:
      - alert: SlowDownload
        # Adjust the threshold to your plan — e.g. half of advertised speed.
        expr: speedtest_download_bits_per_second / 1e6 < 100
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "ISP download speed degraded"
          description: "Average download <100 Mbps for 1h ({{ $value | printf \"%.1f\" }} Mbps)."

      - alert: HighPing
        expr: speedtest_ping_ms > 50
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "High latency to upstream"
          description: "Ping >50ms for 1h ({{ $value | printf \"%.1f\" }}ms)."
```

Reload Prometheus afterwards.

## Daily commands

```bash
docker compose logs -f speedtest-tracker     # live logs
docker compose restart speedtest-tracker     # after .env tweak
docker compose pull && docker compose up -d  # upgrade
docker compose down                          # stop, keep history
docker compose down -v                       # ALSO wipes test history
```

To trigger a one-off test from the CLI:

```bash
docker compose exec speedtest-tracker php artisan app:run-speedtest
```

## Backups

The `speedtest-data` named volume holds the SQLite DB with all historical tests. Backed up by the NAS via `/var/lib/docker/volumes/` — see `../backups/`. Lightweight; megabytes per year at hourly tests.

## Pinning to specific servers (optional)

Auto-selection picks the geographically closest server each run, which sounds good but produces noisier graphs (different servers have different routing quality). For cleaner long-term data, pin to 1–3 specific servers.

Find IDs:

```bash
docker compose exec speedtest-tracker speedtest --servers | head -20
```

Then in `.env`:

```
SPEEDTEST_SERVERS=12345,67890
```

Restart. The tracker now rotates between only those servers.

## Security posture

| Mitigation | Why |
|------------|-----|
| Pinned image tag | No silent upgrades |
| APP_KEY required (`:?` guard) | Won't start with empty key |
| Runs as PUID/PGID (not root) | No root-owned files in /config |
| Own docker network | Doesn't reach other stacks |
| Web UI requires admin account | No anonymous access |

## Troubleshooting

**"Could not find required APP_KEY"**
You didn't generate one. See step 1.

**Test runs hang or fail**
Ookla's `speedtest` CLI sometimes needs to accept the license on first run. `docker compose exec speedtest-tracker speedtest --accept-license --accept-gdpr` then try again.

**Prometheus scrape returns 404**
Check `PROMETHEUS_ENABLED: "true"` is set (it is in our compose file). The path is `/api/metrics/prometheus`, not `/metrics`.

**Graphs are super spiky**
Auto-selecting servers is noisy. Pin to specific server IDs (see above).
