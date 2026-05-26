# Immich

Self-hosted photo + video backup. Phone app auto-uploads in the background; AI search ("photos of my dog on a beach"); face recognition; albums; sharing. Closest thing to a drop-in Google Photos replacement.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `ghcr.io/immich-app/immich-server:v1.121.0` | `2283` | API + web UI |
| `ghcr.io/immich-app/immich-machine-learning:v1.121.0` | *not exposed* | Face recognition, CLIP search |
| `ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0` | *not exposed* | Metadata DB (must be the vector variant) |
| `redis:6.2-alpine` | *not exposed* | Job queue |

All four images must run matching `IMMICH_VERSION`. Bump them together.

## Prerequisites

- Docker + Compose — see `../docker/`.
- A path with **enough disk space for your photo library** plus ~20% for thumbnails / transcodes / database.
- Optional: Cloudflare Tunnel for remote access — see `../cloudflared/`.

**Rough storage estimate:** the original files dominate. Add ~15% for thumbs + previews + Postgres. If your phone library is 200 GB, plan for ~250 GB.

## One-time setup

### 1. Pick the library path

Decide where `UPLOAD_LOCATION` will point. Options:

- **Local disk on the homelab host** — e.g. `/srv/immich/library`. Fast. Limited by host disk size.
- **NAS share mounted on the host** — e.g. `/mnt/nas/immich`. Mount via NFS or SMB in `/etc/fstab` before bringing Immich up. Survives a homelab host wipe (the NAS still has the files).
- **Immich running directly on the NAS** — if your NAS supports Docker Compose. Then `UPLOAD_LOCATION` is just a local path on the NAS. Best long-term option if the NAS has the CPU for it.

Create the directory and make sure the user Docker runs as can write to it:

```bash
sudo mkdir -p /srv/immich/library
sudo chown -R "$USER:$USER" /srv/immich
```

### 2. Configure and start

```bash
cp .env.example .env
nano .env
```

Set at minimum:
- `UPLOAD_LOCATION` — the path you picked in step 1
- `DB_PASSWORD` — a real password (anything random)
- `TZ` — your timezone

Then:

```bash
docker compose up -d
docker compose logs -f immich-server
```

First start takes 30–60s while Postgres runs initial migrations. Wait for `Immich Server is listening on port 2283`.

### 3. Create your admin account

Browse to `http://<host>:2283`. The first user you create is the admin — there's no public signup after this point.

Pick a real password. The web UI shows you a one-time recovery key — save it somewhere safe.

### 4. Add the mobile app

iOS / Android: search **Immich** in the App Store / Play Store. On first launch, tap **Add server endpoint** and enter:

- LAN-only: `http://<host>:2283`
- Via Cloudflare Tunnel: `https://photos.yourdomain.com`

Log in, then **Settings → Backup** → enable both *Photos* and *Videos* → background mode on. The first backup will take a while (potentially days for large libraries on slow networks).

### 5. Optional: expose via Cloudflare Tunnel

In the Zero Trust dashboard → your tunnel → **Public Hostname** → **Add**:

| Subdomain | Domain | Service type | URL |
|-----------|--------|--------------|-----|
| `photos` | `yourdomain.com` | HTTP | `host.docker.internal:2283` |

**Don't** add a Cloudflare Access policy in front. Same problem as Vaultwarden — the mobile app authenticates against the API directly and can't complete a browser OTP flow. Immich's own auth (your admin account + 2FA if you enable it under Account Settings) protects it.

If you want a second layer, configure CF WAF rules (rate limit, geo-block) — those operate at the request layer without breaking clients.

## Daily commands

```bash
docker compose logs -f immich-server         # live server logs
docker compose logs -f immich-machine-learning  # ML job logs
docker compose ps                            # is everything healthy?
docker compose restart immich-server         # after .env tweak
docker compose pull && docker compose up -d  # upgrade — see Upgrading
docker compose down                          # stop, keep data
docker compose down -v                       # ALSO wipes DB and ML model cache
```

`down -v` does **not** delete photos in `UPLOAD_LOCATION` — that's a bind mount. It does delete the database (= all metadata, albums, users, AI tags). The photos will reappear but you'd need to re-create albums and re-run face recognition.

## Upgrading

Immich ships fast and **almost every release includes DB schema migrations**. Don't blindly pull `:latest`.

```bash
# 1. Read the release notes:
#    https://github.com/immich-app/immich/releases
#    Look for "BREAKING" or "MIGRATION" notices.
# 2. Back up the database (see below) — once a migration runs, you can't roll back.
# 3. Bump IMMICH_VERSION in .env.
# 4. Pull and recreate:
docker compose pull
docker compose up -d
# 5. Watch the server logs until migrations complete and "listening on port 2283" appears.
docker compose logs -f immich-server
```

If a migration fails mid-way, restore the DB backup from step 2 and downgrade the version pin.

## Backups (Postgres needs special handling)

The standard NAS rsync of `/var/lib/docker/volumes/` (see `../backups/`) captures the Postgres data files — but a live Postgres directory can be in an inconsistent state at the moment rsync starts. For metadata you can re-derive (face recognition re-runs etc.), that's fine. For irreplaceable metadata (album organisation, sharing links), use `pg_dump`:

```bash
# On the homelab, scheduled via cron:
docker compose exec -T database \
  pg_dump --username=postgres --dbname=immich \
  | gzip > /srv/immich/backups/immich-db-$(date +%F).sql.gz
```

The NAS picks up these tarballs alongside the photo originals. They're tiny (megabytes) compared to the photo library.

**The photo files themselves** in `UPLOAD_LOCATION` are just regular files; the NAS rsync handles them like any other directory. They are the irreplaceable part — guard them.

## Hardware acceleration

Default is CPU-only. Works fine for libraries up to a few thousand photos; gets slow for tens of thousands or 4K video.

**Video transcoding** (FFmpeg) — uncomment the `devices:` and `group_add:` blocks under `immich-server` in `docker-compose.yml`, set `RENDER_GID` in `.env`.

**ML acceleration** — switch the `immich-machine-learning` image tag:

| Hardware | Image tag |
|----------|-----------|
| NVIDIA GPU (CUDA) | `ghcr.io/immich-app/immich-machine-learning:v1.121.0-cuda` |
| Intel iGPU (OpenVINO) | `:v1.121.0-openvino` |
| ARM Mali GPU | `:v1.121.0-armnn` |
| CPU only (default) | `:v1.121.0` |

See https://immich.app/docs/features/ml-hardware-acceleration for the full setup per hardware.

## Storage growth alerts

Photo libraries grow forever. Add an Alertmanager rule for the filesystem holding `UPLOAD_LOCATION`. The default rules in `../monitoring/prometheus/rules/alerts.yml` already cover this if it's on the homelab host's root disk — adjust the filesystem filter if it lives on a separate mount.

## Security posture

| Mitigation | Why |
|------------|-----|
| All four image tags pinned | DB schema migrations make `:latest` dangerous |
| Postgres / Redis / ML not exposed to host | Only `immich-server` has a host port; the rest are docker-network-only |
| DB_PASSWORD required (`:?` guard) | Won't start with default/empty |
| Own docker network | Immich services can't reach other stacks; other stacks can't reach Postgres |
| First user = admin, no public signup | Same pattern as Vaultwarden |
| No CF Access in front | Mobile app needs direct API auth; use CF WAF rules instead if you want a layer |
| Backups via NAS + pg_dump | `../backups/` covers files; pg_dump above covers DB consistently |

## Troubleshooting

**`docker compose up` fails: "set in .env"**
You haven't set `DB_PASSWORD` or `UPLOAD_LOCATION`. The `:?` guard is doing its job.

**Server logs: "relation does not exist" or migration errors**
You're upgrading across a major version without reading release notes. Roll back `IMMICH_VERSION`, restore the DB backup, then upgrade one minor version at a time.

**Server logs: "could not connect to database"**
Postgres took longer than expected to come up. The `depends_on: service_healthy` should handle this, but if Postgres itself is broken (image mismatch, corrupted volume), it'll fail. Check `docker compose logs database`.

**Mobile app: "no server found"**
Wrong URL. LAN must use `http://`; via the tunnel must use `https://`. No trailing slash. No port in the URL when using the tunnel.

**ML jobs (face recognition) stuck queued**
`docker compose logs immich-machine-learning`. First run downloads ~1-3 GB of models — be patient. After that it should be sub-second per photo on CPU, faster on GPU.

**Filesystem full**
You've hit your disk. Move `UPLOAD_LOCATION` to a bigger disk (see https://immich.app/docs/administration/backup-and-restore#external-libraries), or add another volume to the host. Don't ignore the disk alerts.
