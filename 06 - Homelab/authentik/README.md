# Authentik

Self-hosted Identity Provider. One login screen that fronts everything else in the homelab — Grafana, Immich, Uptime Kuma, Forgejo (when you add it), and any future service that speaks OAuth2 / OIDC / SAML.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `ghcr.io/goauthentik/server:2024.10.4` (server) | `9000` / `9443` | Login UI, OIDC/SAML endpoints, admin API |
| `ghcr.io/goauthentik/server:2024.10.4` (worker) | *not exposed* | Background jobs |
| `postgres:16-alpine` | *not exposed* | User/group/session storage |
| `redis:alpine` | *not exposed* | Cache + task queue |

Server and worker run from the same image but with different commands — both tags must match.

## Why bother

You've got ~10 services now. Each has its own auth: separate accounts, separate passwords, separate 2FA. SSO collapses that to *one* login the rest of the day. Bigger payoffs:

| | Without Authentik | With Authentik |
|---|---|---|
| New service onboarding | Create user, set password, configure 2FA, share creds with anyone else who needs it | Add an application in Authentik, click Save. Done. |
| User offboarding | Hunt through every service to remove the account | Disable the user once in Authentik |
| Password policy | Per service, inconsistently enforced | One place, applied everywhere |
| MFA | Per service, often missing | Enforced at the IdP — every login goes through it |
| Audit | Each service has its own log format | One audit log of every login |

It also unlocks `OAuth2 outpost` (or `proxy outpost`) — a reverse-proxy mode that protects services that don't speak OAuth natively (Grafana sort of does, Jellyfin doesn't).

## Prerequisites

- Docker + Compose — see `../docker/`.
- A subdomain decided — `auth.yourdomain.com` is the convention used here.
- Cloudflare Tunnel running — see `../cloudflared/`.

## One-time setup

### 1. Generate the two required secrets

```bash
openssl rand -base64 36                  # for PG_PASS
openssl rand -base64 60 | tr -d '\n'     # for AUTHENTIK_SECRET_KEY
```

Both go into `.env`. The secret key signs every cookie and token — treat it like a master credential.

### 2. Add the Cloudflare Tunnel route

In the Zero Trust dashboard → your tunnel → **Public Hostname** → **Add**:

| Subdomain | Domain | Service type | URL |
|-----------|--------|--------------|-----|
| `auth` | `yourdomain.com` | HTTP | `host.docker.internal:9000` |

No CF Access policy here — Authentik IS the access policy from here on.

### 3. Bring it up

```bash
cp .env.example .env
nano .env                  # paste both secrets, set email or leave blank
docker compose up -d
docker compose logs -f server
```

First start takes 30–60s for DB migrations. Wait for `running migrations` to complete and `Booting worker` to appear.

### 4. Complete the initial-setup flow

Open `https://auth.yourdomain.com/if/flow/initial-setup/` (yes, the trailing slash matters). Authentik asks you to:

1. Set the admin (`akadmin`) password
2. Optionally configure email

Once you set the password, the initial-setup flow disables itself — you can't accidentally re-trigger it.

### 5. Lock down the admin user

In **Directory → Users → akadmin → MFA Authenticators**: add an authenticator app (Aegis / 2FAS / etc.). Authentik will then prompt for the TOTP on every admin login.

## Connecting services (the actually-fun part)

Each service plugs in differently. Order of operation in Authentik is always the same:

1. **Provider** — defines the protocol (OIDC, SAML, Proxy, LDAP)
2. **Application** — what users see in the Authentik dashboard, points at the provider
3. **Outpost** (only for proxy auth) — runs an embedded reverse-proxy that enforces login before forwarding to the backend service

### OIDC example — Grafana

In **Authentik admin → Applications → Providers → Create**:

- Type: **OAuth2 / OpenID Provider**
- Authorization flow: `default-provider-authorization-implicit-consent`
- Client ID: auto-generated, copy it
- Client Secret: auto-generated, copy it
- Redirect URIs: `https://grafana.yourdomain.com/login/generic_oauth`

Then **Applications → Create**, link the provider.

On the Grafana side, edit `../monitoring/.env`:

```
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_NAME=Authentik
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=<from authentik>
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=<from authentik>
GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email
GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://auth.yourdomain.com/application/o/authorize/
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://auth.yourdomain.com/application/o/token/
GF_AUTH_GENERIC_OAUTH_API_URL=https://auth.yourdomain.com/application/o/userinfo/
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true
```

`cd ../monitoring && docker compose up -d grafana`. The Grafana login page now has an "Authentik" button alongside the username/password form.

### Proxy outpost example — Jellyfin

Jellyfin doesn't speak OAuth. The proxy outpost mode handles this:

1. In Authentik: **Applications → Providers → Create → Proxy Provider**
   - External host: `https://jellyfin.yourdomain.com`
   - Internal host: `http://host.docker.internal:8096` (or wherever Jellyfin lives)
   - Mode: **Forward auth (single application)**
2. Create the matching application.
3. **Outposts → Create → Proxy outpost**, attach the application.

Authentik generates a docker-compose snippet for the outpost (a small Go binary). Run that alongside this stack. Then update the CF Tunnel route for `jellyfin.yourdomain.com` to point at the **outpost's port** instead of Jellyfin directly. Anyone hitting `jellyfin.yourdomain.com` now sees the Authentik login first.

**Caveat:** the native Jellyfin apps still can't complete a browser SSO flow. Use the web client behind Authentik, native apps over LAN/Tailscale. Same Jellyfin caveat as before — the proxy outpost is for the web UI, not API auth.

### Services worth wiring up first

| Service | Method | Difficulty |
|---------|--------|------------|
| Grafana | OIDC native | Easy |
| Forgejo (if added) | OIDC native | Easy |
| Immich | OIDC native | Easy |
| Uptime Kuma | None native | Skip, or proxy outpost |
| Jellyfin | None native | Proxy outpost for web, accept native apps stay separate |
| Vaultwarden | None native | **Don't bother** — its own auth + 2FA is already strong, and proxy outpost breaks the apps |

## Backups

The `authentik-database` and `authentik-media` named volumes are the critical state. The `authentik-redis` volume is regenerable.

The standard NAS rsync of `/var/lib/docker/volumes/` catches them (see `../backups/`). For point-in-time DB consistency:

```bash
docker compose exec -T postgresql \
  pg_dump --username=authentik --dbname=authentik \
  | gzip > /srv/authentik/backups/authentik-db-$(date +%F).sql.gz
```

**Test the restore.** Losing Authentik means losing access to every service behind it.

## Daily commands

```bash
docker compose logs -f server         # live login attempts, errors
docker compose logs -f worker         # background job activity
docker compose ps                     # all four containers healthy?
docker compose restart server         # after .env tweak
docker compose pull && docker compose up -d   # upgrade
```

## Upgrading

Read the release notes for breaking changes: https://goauthentik.io/docs/releases/

```bash
# 1. Back up the DB (pg_dump above)
# 2. Bump AUTHENTIK_VERSION in .env
# 3. Pull and recreate
docker compose pull
docker compose up -d
# 4. Watch migrations
docker compose logs -f server
```

## Security posture

| Mitigation | Why |
|------------|-----|
| All four image tags pinned | DB migrations make floating tags dangerous |
| Postgres + Redis not exposed to host | Only the server has a host port |
| `AUTHENTIK_SECRET_KEY` required (`:?` guard) | Won't start with empty/default key |
| Admin user (`akadmin`) requires manual password set | No factory-default credentials |
| MFA enforced at the IdP | Every downstream service gets MFA for free |
| Worker has no docker socket | Outposts deployed as separate compose stacks instead |
| Own docker network | Authentik's services can't reach other stacks |

## Troubleshooting

**`https://auth.yourdomain.com` shows a Cloudflare error**
Tunnel route not set or pointing at the wrong port. Should be `host.docker.internal:9000` (HTTP) — *not* 9443.

**Initial setup link returns 404**
You missed the trailing slash. Use `https://auth.yourdomain.com/if/flow/initial-setup/` literally.

**Service redirects to login, login succeeds, redirects back to login (loop)**
Cookie domain mismatch. Authentik and the service must share a parent domain (both under `yourdomain.com`) for cookies to work. Cross-domain SSO needs OIDC, not cookie-based proxy.

**OIDC works in browser but not from a mobile app**
Same caveat as Vaultwarden — most mobile apps don't implement OIDC. Use the proxy outpost for web, accept native apps stay outside the SSO bubble or use service tokens.

**Worker keeps restarting**
Usually a Postgres or Redis connectivity issue. `docker compose logs worker` — first lines tell you which.
