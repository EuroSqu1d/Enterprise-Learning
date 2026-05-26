# Jellyfin

Self-hosted media server. Web UI on port `8096`.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `jellyfin/jellyfin:10.10.3` | `8096` | Web UI + API |

Pinned tag. Bump procedure: edit the tag in `docker-compose.yml`, then `docker compose pull && docker compose up -d`.

## Prerequisites

- Docker Engine + Compose plugin — see `../docker/`.
- A directory on the host containing your media (e.g. `/srv/media/Movies`, `/srv/media/Shows`).
- The UID/GID of the user that owns that directory (`id -u`, `id -g`).

## First-time setup

```bash
cp .env.example .env
# edit .env — at minimum set PUID, PGID, MEDIA_PATH, JELLYFIN_URL
docker compose up -d
docker compose ps
```

Then browse to `http://<host>:8096`. The first-launch wizard asks you to:
1. Create the admin user (this is the only account that can change server settings).
2. Add a library — point it at `/media/Movies` (inside the container) which maps to `<MEDIA_PATH>/Movies` on the host. Repeat for Shows, Music, etc.
3. Pick metadata providers (TMDB, TVDB, etc.). Defaults are fine.

The first scan takes a while (minutes to hours depending on library size). Watch progress in the admin dashboard.

## Daily commands

```bash
docker compose logs -f jellyfin   # live logs
docker compose restart jellyfin   # after editing .env or compose
docker compose pull && docker compose up -d   # upgrade
docker compose down               # stop, keep config + cache
docker compose down -v            # stop AND wipe config + cache
```

## Hardware transcoding (optional)

If the host has an Intel iGPU (most consumer CPUs after ~2015) or a recent AMD GPU, uncomment the `devices:` and `group_add:` blocks in `docker-compose.yml`, set `RENDER_GID` in `.env`, then:

```bash
docker compose up -d
```

In the Jellyfin admin dashboard → *Playback* → *Transcoding*, set **Hardware acceleration** to "Intel QuickSync (QSV)" or "VAAPI", tick the codecs your GPU supports, save.

Test by playing a 4K file from a phone — the transcode should pin GPU usage, not CPU.

## Security notes

The mitigations baked into `docker-compose.yml` (also explained inline as comments):

| Mitigation | Why |
|------------|-----|
| Pinned image tag | No silent upgrades; no image-swap supply chain risk |
| Bridge network + explicit port mapping (not host networking) | Container can't see host network interfaces; smaller blast radius |
| Media mounted `:ro` | Plugin/exploit can't modify or delete your media |
| Runs as host user (PUID:PGID), not root | No root-owned files appearing in `/media`; ordinary user can manage files normally |
| HTTPS port 8920 NOT exposed | Use a reverse proxy for TLS instead — much easier to manage certs centrally |
| Own docker network (not shared with `monitoring/`) | Media server can't reach Prometheus/Loki or vice versa |

## Adding more libraries

In `docker-compose.yml` duplicate the media volume line:

```yaml
- ${MEDIA_PATH}:/media:ro
- /mnt/music:/media/music:ro
- /mnt/audiobooks:/media/audiobooks:ro
```

`docker compose up -d` to apply. Then add libraries in the Jellyfin UI pointing at `/media/music` and `/media/audiobooks` respectively.

## Backups

What matters is the `jellyfin-config` volume — that's your users, watch state, library metadata. Cache (`jellyfin-cache`) is rebuildable.

```bash
# Quick tarball backup
docker run --rm -v jellyfin-config:/data -v "$PWD":/backup alpine \
  tar czf /backup/jellyfin-config-$(date +%F).tar.gz -C /data .
```

Restore: stop the stack, wipe the volume, extract the tarball back into a fresh volume, start.

## Troubleshooting

**Web UI doesn't load** — `docker compose logs jellyfin`. Usually a port collision (something else on 8096) or PUID/PGID can't read MEDIA_PATH.

**Library is empty** — Permissions. Run `ls -la <MEDIA_PATH>` and confirm PUID has read access. Common fix: `sudo chown -R <youruser>:<youruser> <MEDIA_PATH>`.

**Remote clients connect but playback fails** — `JELLYFIN_URL` in `.env` is wrong. It must be reachable from wherever the client is (LAN IP for LAN, public URL for over-internet).

**Choppy 4K playback on weak clients** — Enable hardware transcoding (see above).
