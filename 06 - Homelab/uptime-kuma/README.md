# Uptime Kuma

Lightweight uptime monitor with a built-in status page. Web UI on port `3001`.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `louislam/uptime-kuma:1.23.16-alpine` | `3001` | Probes + status page |

## Why use this alongside the monitoring stack?

Prometheus + Alertmanager + blackbox_exporter already do uptime monitoring, so on paper Kuma is redundant. It earns its space by adding things the metrics stack doesn't do well:

| | Metrics stack | Uptime Kuma |
|---|---|---|
| Pretty public status page | Build yourself | Out of the box |
| Independent watchdog (catches monitoring crashes) | — | Yes — separate process, separate state |
| Push / heartbeat monitoring ("did my cron run?") | — | Yes |
| Add a check via clicking | No, edit YAML | Yes, web form |
| Resource cost | — | ~50 MB RAM, negligible CPU |

Use Prometheus + blackbox as the **primary**, alerting source-of-truth. Use Kuma for **status pages**, **heartbeat checks** (backup cron, anything scheduled), and as a **second pair of eyes** so a Prometheus outage doesn't blind you to real failures.

## Run

```bash
docker compose up -d
```

Open `http://<host>:3001` — the first visit prompts you to create an admin user. No `.env` file needed; Kuma manages its own config.

## What to add first

Start with these to get value quickly:

1. **HTTP monitors** for each public URL behind your Cloudflare Tunnel — `https://grafana.yourdomain.com`, `https://jellyfin.yourdomain.com`. Heartbeat interval 60s is plenty.
2. **Heartbeat (push) monitor** for the NAS backup job — see *Heartbeat checks* below.
3. **A status page** at *Settings → Status Pages → New* listing the monitors above. Bookmark its URL.

## Heartbeat checks (catch failing cron jobs)

This is the unique-to-Kuma feature worth using:

1. In Kuma: *Add New Monitor* → **Type: Push** → set a name (e.g. "NAS nightly backup") → save.
2. Kuma gives you a URL like `http://<host>:3001/api/push/AbC123xyZ?status=up&msg=OK&ping=`.
3. Append a `curl` to whatever script you want to monitor:

   ```bash
   # in your NAS backup script, last line:
   curl -fsS -m 10 --retry 3 "http://<homelab>:3001/api/push/AbC123xyZ"
   ```

4. If Kuma doesn't hear from it within the configured interval (default 60s with a 2-minute grace), it fires the monitor red.

Now you're not just monitoring "is the service up" — you're monitoring "did this scheduled thing actually run".

## Status page behind Cloudflare Access

To share with family/non-techies:

1. Create a status page in Kuma (*Settings → Status Pages*).
2. Add a public hostname route in your Cloudflare Tunnel: `status.yourdomain.com` → `http://host.docker.internal:3001`.
3. In Cloudflare Access, either:
   - Leave it fully public (anyone can see "is the homelab up"), or
   - Allow specific emails only (family).

## Notifications

Kuma has its own notification channels (Discord, Slack, ntfy, Telegram, email, Gotify, Apprise, dozens more). Configure them under *Settings → Notifications*.

You can wire the **same Discord/Slack webhook** you used in Alertmanager — both systems then post to the same channel. Bit of duplication when something's really down, but you'll never miss it.

## Daily commands

```bash
docker compose logs -f uptime-kuma
docker compose restart uptime-kuma
docker compose pull && docker compose up -d   # upgrade — check release notes first
docker compose down
docker compose down -v        # also wipes monitors + history
```

## Backups

The `uptime-kuma-data` named volume contains the SQLite DB with all monitor definitions, notification configs, status page settings, and historical uptime data. Backed up by the NAS along with everything else under `/var/lib/docker/volumes/` — see `../backups/`.

## Security notes

| Mitigation | Why |
|------------|-----|
| Pinned image tag | No silent upgrades (Kuma 1.x → 2.x will need a migration) |
| Own docker network | Can't reach other stacks' internal traffic |
| No env file with credentials | Kuma manages its own auth — admin created on first visit |
| Behind Cloudflare Access if exposed | Use the same Access pattern as the other services |
