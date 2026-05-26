# Cloudflare Tunnel

Outbound-only secure tunnel that exposes selected homelab services on `https://<name>.yourdomain.com` without opening any inbound ports. Survives behind CGNAT, firewalls, and corporate WiFi that blocks VPN apps.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `cloudflare/cloudflared:2024.10.1` | *none — outbound only* | Tunnel client |

## Prerequisites

- A domain managed in Cloudflare (nameservers pointed at CF).
- Cloudflare **Zero Trust** enabled on your account (free tier is fine for personal use).
- Docker on the host — see `../docker/`.

## One-time Cloudflare setup

1. Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels** → **Create a tunnel** → **Cloudflared**.
2. Name it something like `mikoshi` (the host it'll run on).
3. On the "Install and run a connector" screen, copy the long string after `--token` in the Docker example — that whole blob is your `TUNNEL_TOKEN`.
4. **Public Hostname** tab → **Add a public hostname**. Repeat for each service:

   | Subdomain | Domain | Service type | URL |
   |-----------|--------|--------------|-----|
   | `grafana` | `yourdomain.com` | HTTP | `host.docker.internal:3000` |
   | `jellyfin` | `yourdomain.com` | HTTP | `host.docker.internal:8096` |
   | `prometheus` *(optional)* | `yourdomain.com` | HTTP | `host.docker.internal:9090` |

   `host.docker.internal` works because of the `extra_hosts` mapping in `docker-compose.yml`. Cloudflare automatically creates the DNS records for you.

## Run

```bash
cp .env.example .env
# paste your token into .env
docker compose up -d
docker compose logs -f cloudflared
```

In the logs you should see lines like `Registered tunnel connection` four times (one per CF edge data centre). The tunnel is now live.

Test by visiting `https://grafana.yourdomain.com` in any browser — including from your locked work laptop.

## Update Grafana + Jellyfin to know their public URLs

Without this step, login redirects and stream URLs will point at `localhost`.

**Grafana** — edit `../monitoring/.env`:
```
GF_SERVER_ROOT_URL=https://grafana.yourdomain.com
```
Then `cd ../monitoring && docker compose up -d`.

**Jellyfin** — edit `../jellyfin/.env`:
```
JELLYFIN_URL=https://jellyfin.yourdomain.com
```
Then `cd ../jellyfin && docker compose up -d`.

## Lock it down with Cloudflare Access (recommended)

By default, anyone who knows the hostname can reach the login page. Add a second auth layer in front:

1. Zero Trust → **Access** → **Applications** → **Add an application** → **Self-hosted**.
2. Application domain: `grafana.yourdomain.com` (one app per hostname).
3. Add a policy: e.g. *"Allow if email matches your-personal-email@…"* or *"Allow if email ends in @yourdomain"*.
4. Save.

Now hitting `grafana.yourdomain.com` from anywhere bounces you to a CF email-OTP login first, then to Grafana. Even if your Grafana admin password leaks, no one without your email reaches the app.

For the **work laptop scenario**: Access uses an emailed one-time PIN by default, so it works in any browser without installing anything corporate IT might block.

## Daily commands

```bash
docker compose logs -f cloudflared     # watch tunnel health
docker compose restart cloudflared     # after rotating the token
docker compose pull && docker compose up -d   # upgrade
```

## Updating cloudflared

Cloudflare releases monthly-ish. Check [Docker Hub](https://hub.docker.com/r/cloudflare/cloudflared/tags) for the current tag, edit `docker-compose.yml`, then:

```bash
docker compose pull
docker compose up -d
```

`--no-autoupdate` in the compose command stops cloudflared from upgrading itself behind your back, so the pinned tag stays the source of truth.

## Security notes

| Mitigation | Why |
|------------|-----|
| No inbound ports opened on your router | Tunnel is outbound from cloudflared to CF edge |
| Pinned image tag + `--no-autoupdate` | No silent client changes |
| Own docker network | cloudflared can't reach other containers laterally — only services on the host's published ports |
| `host.docker.internal` instead of host networking | cloudflared keeps its own network namespace |
| `TUNNEL_TOKEN:?` guard | Refuses to start without a token |
| Cloudflare Access (optional) | Second auth layer in front of every app |

**Token handling:** The token is sensitive. Store it only in `.env` (gitignored) or a secrets manager. If you ever paste it somewhere by accident, immediately go to Zero Trust → Tunnels → your tunnel → *Refresh token*. The old token dies instantly.

## Jellyfin + Cloudflare ToS (read this)

Cloudflare's TOS section 2.8 prohibits using their free proxy as a CDN for "a disproportionate percentage of pictures, audio files, or videos". Streaming a few episodes to yourself from work is a non-issue in practice. Risks scale with traffic — you start hearing about warnings around sustained terabytes/month or many concurrent users.

Practical guidance for a personal homelab:
- Single user, occasional streaming → fine.
- Heavy sharing with family/friends or constant high-bitrate streaming → consider Tailscale on personal devices for streams, keeping CF Tunnel only for the admin UI.

## Troubleshooting

**`docker compose logs` shows "Unauthorized" or "Failed to dial"**
Token is wrong, copied with a trailing space, or you regenerated it in the dashboard. Re-copy and restart.

**Tunnel connects but `https://grafana.yourdomain.com` returns 502**
cloudflared can't reach the backend. Confirm `docker ps` shows grafana running and `curl http://localhost:3000` works on the host. If yes, double-check the dashboard route uses `host.docker.internal:3000`, not `localhost:3000` (localhost inside the container is the container itself).

**Login loops in Grafana**
You forgot `GF_SERVER_ROOT_URL`. Grafana redirects to whatever it thinks its public URL is; if that's still `http://localhost:3000`, login redirects break.

**Cloudflare Access email never arrives**
Check spam. Also confirm in *Settings → Authentication* that "One-time PIN" is enabled as a login method.
