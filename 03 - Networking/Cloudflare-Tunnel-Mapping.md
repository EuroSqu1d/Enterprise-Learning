# Cloudflare Tunnel Mapping

Single table tracking which public hostnames go to which internal services, and what's protecting them.

| Public hostname | Service | Internal target | CF Access? | Notes |
|-----------------|---------|-----------------|------------|-------|
| `grafana.yourdomain.com` | Grafana | `host.docker.internal:3000` | Optional (email OTP) | Email-OTP works for browser; native dashboards are browser-only anyway |
| `photos.yourdomain.com` | Immich | `host.docker.internal:2283` | **No** — breaks mobile app | Immich's own auth |
| `vault.yourdomain.com` | Vaultwarden | `host.docker.internal:8200` | **No** — breaks mobile/extension apps | Strong master password + 2FA |
| `auth.yourdomain.com` | Authentik | `host.docker.internal:9000` | **No** — Authentik IS the access policy | |
| `jellyfin.yourdomain.com` | Jellyfin | `host.docker.internal:8096` | Optional, only for web client | Native apps must bypass |
| `matrix.yourdomain.com` | Matrix (Conduit) | `host.docker.internal:8448` | **No** — clients use direct API auth | |
| `status.yourdomain.com` | Uptime Kuma status page | `host.docker.internal:3001` | Public *or* allow-family | |
| `proxmox.yourdomain.com` | Proxmox web UI | `https://10.0.10.11:8006` | **Yes** — admin surface | Must use HTTPS for tunnel origin since Proxmox UI is HTTPS-only |
| (Future) `n8n.yourdomain.com` | (Add when deployed) | | | |

## Bare-domain special cases

Some services need files served at the *root* domain, not a subdomain:

| Path | Purpose | Implementation |
|------|---------|----------------|
| `yourdomain.com/.well-known/matrix/server` | Matrix federation discovery | Cloudflare Worker (see `../06 - Homelab/matrix/README.md`) |
| `yourdomain.com/.well-known/matrix/client` | Matrix client discovery | Same worker |

## CF Access policy reference

Where policies *are* applied (admin-surface stuff), the standard pattern is:

- **Authentication**: Email OTP
- **Allowed emails**: your personal + a backup
- **Session duration**: 24 hours

Configured per-app in Zero Trust → Access → Applications.

## When you add a tunnel hostname

1. Reserve the subdomain — pick a short, obvious name (`<service>.yourdomain.com`).
2. Add the Public Hostname in the Zero Trust dashboard pointing at `host.docker.internal:<port>`.
3. Decide CF Access policy. **Default is "yes, email OTP"** for any admin UI; **default is "no"** for anything with native mobile/desktop clients (Vaultwarden, Immich, Matrix, Jellyfin native apps).
4. Update this table.
5. Add the matching split-horizon rewrite in AdGuard Home (`DNS-Plan.md`).
6. Update `GF_SERVER_ROOT_URL` / `DOMAIN` / `JELLYFIN_URL` / etc. in the service's `.env` to its public URL.
