# Vaultwarden

Self-hosted Bitwarden-compatible password manager. The official Bitwarden browser extensions and mobile apps all work — just point them at your homelab instead of `bitwarden.com`.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `vaultwarden/server:1.32.5` | `8200` | Web vault + API |

## Prerequisites

- Docker + Compose — see `../docker/`.
- Cloudflare Tunnel up — see `../cloudflared/`. Vaultwarden **requires HTTPS**; the Bitwarden apps refuse plain HTTP.
- A subdomain decided — `vault.yourdomain.com` is the convention used in these docs.

## One-time setup

### 1. Add a Cloudflare Tunnel route

In the Zero Trust dashboard → your tunnel → **Public Hostname** → **Add**:

| Subdomain | Domain | Service type | URL |
|-----------|--------|--------------|-----|
| `vault` | `yourdomain.com` | HTTP | `host.docker.internal:8200` |

Save — CF creates the DNS record automatically. **Don't** add Access policies in front (see *Cloudflare Access caveat* below).

### 2. Prepare `.env`

```bash
cp .env.example .env
nano .env
```

- Set `DOMAIN=https://vault.yourdomain.com` to match the route you just created.
- Leave `SIGNUPS_ALLOWED=true` for now — you'll flip it after step 4.
- Leave `ADMIN_TOKEN=` empty for now.

### 3. Bring it up

```bash
docker compose up -d
docker compose logs -f vaultwarden
```

Wait for `Listening for new connections` in the logs.

### 4. Create your account

In a browser go to `https://vault.yourdomain.com`. Click **Create account**, register with a strong master password, log in.

**Important:** the master password is the only thing standing between an attacker and every password you ever store here. Pick a long passphrase. Write it down somewhere offline. There is no recovery — lose it and the vault is bricked.

### 5. Lock down signups

```bash
nano .env       # change to SIGNUPS_ALLOWED=false
docker compose up -d
```

From this point on, nobody can register a new account on your server. Existing invitations and your account still work fine.

### 6. Turn on 2FA

In Vaultwarden → **Settings → Security → Two-step Login**. Enable **Authenticator App** with whatever you use (Aegis, 2FAS, Bitwarden Authenticator, etc.). 2FA on the vault itself is non-negotiable — it's the master credential for everything else.

## Cloudflare Access caveat (read this)

It's tempting to put Vaultwarden behind a Cloudflare Access policy like you did for Jellyfin. **Don't.**

The Bitwarden browser extension, mobile apps, and desktop apps authenticate directly against the Vaultwarden API. They can't complete a CF Access email-OTP browser flow, so Access would break every client except the web vault.

Vaultwarden's own security stack is what protects you:
- Long master password (you chose this)
- 2FA (you turned this on in step 6)
- `SIGNUPS_ALLOWED=false` (only you have an account)
- Per-IP login throttling
- Argon2 KDF on the master password

That's enough for a single-user homelab vault. If you do want a second auth layer, use **Cloudflare WAF rules** (rate limiting, geo block, bot fight mode) — those operate at the request layer and don't break clients.

## Connecting the apps

| App | Where to set the server URL |
|-----|------------------------------|
| Browser extension | Hamburger menu → **Settings** → **Self-hosted environment** → Server URL: `https://vault.yourdomain.com` → Save → log in |
| iOS / Android | Settings cog on login screen → **Self-hosted** → same URL |
| Desktop | Settings cog on login screen → same URL |
| CLI (`bw`) | `bw config server https://vault.yourdomain.com` then `bw login` |

After setting the URL once, everything else is identical to using bitwarden.com.

## Daily commands

```bash
docker compose logs -f vaultwarden       # live logs
docker compose restart vaultwarden       # after .env changes
docker compose pull && docker compose up -d   # upgrade
docker compose down                      # stop, keep data
docker compose down -v                   # stop AND wipe — DO NOT do this casually
```

## Admin panel (when you actually need it)

Enable temporarily:

```bash
# Generate a strong token
openssl rand -base64 48
# Paste into .env as ADMIN_TOKEN=...
docker compose up -d
```

Then browse to `https://vault.yourdomain.com/admin`, paste the token, do what you need (manage users, send test emails, view diagnostics). When you're done:

```bash
# clear ADMIN_TOKEN in .env (leave the line as ADMIN_TOKEN=)
docker compose up -d
```

The /admin route returns 404 again until you re-set the token.

**Argon2-hashed token (recommended for serious deployments):** the plain token sits in `.env` in cleartext. To store only a hash:

```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
# Paste your token at the prompt, copy the long $argon2id$... output,
# paste that into .env as ADMIN_TOKEN='$argon2id$...'
```

Note the single quotes — the `$` characters in the hash will be eaten by the shell otherwise.

## Backups

The `vaultwarden-data` volume holds:
- `db.sqlite3` — the encrypted vault contents
- `attachments/` — file attachments
- `sends/` — files shared via Bitwarden Send
- `icon_cache/`, `rsa_key.*` — regenerable, but easier to back up than to recover

All of this is included in the NAS rsync of `/var/lib/docker/volumes/` — see `../backups/`.

**Test the backup restore on a throwaway host periodically.** A password manager you can't restore is a single point of failure for everything.

## Security posture

| Mitigation | Where |
|------------|-------|
| Pinned image tag | `docker-compose.yml` |
| HTTPS only (via cloudflared) | App refuses plain HTTP anyway |
| Public signups disabled | `SIGNUPS_ALLOWED=false` after step 5 |
| Admin panel off by default | `ADMIN_TOKEN=` empty |
| Real client IP for rate limiting | `IP_HEADER=CF-Connecting-IP` |
| Own docker network | Can't reach other stacks |
| Master password + 2FA | You set these in steps 4 and 6 |
| Backups | NAS via `../backups/` |

## Troubleshooting

**"Failed to connect" in the browser extension**
Server URL has a trailing slash or wrong scheme. Must be exactly `https://vault.yourdomain.com` — no path, no port.

**Login refuses with "Username or password is incorrect" but you're sure**
Per-IP throttling kicked in after failed attempts. Wait 5 minutes, or check Vaultwarden logs.

**Emails (invites, password hints) not arriving**
SMTP not configured, or credentials wrong. Try sending a test from the admin panel.

**`docker compose up -d` fails with "set in .env"**
You haven't set `DOMAIN`. That's the `:?` guard doing its job.

**App says the server version is too old**
You pinned an older tag than your client supports. Bump the tag in `docker-compose.yml` (check release notes first — major versions occasionally need DB migrations).
