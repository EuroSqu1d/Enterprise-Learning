# Matrix (Conduit homeserver)

Self-hosted Matrix homeserver. Federate with friends on `matrix.org` or any other Matrix server, run private rooms, sit on the network long-term without depending on someone else's hosting.

| Image | Host port | Purpose |
|-------|-----------|---------|
| `matrixconduit/matrix-conduit:v0.7.0` | `8448` | Client + federation API |

## What "Matrix" is, in two sentences

Matrix is a federated chat protocol — like email, but for messaging. You run a homeserver (this), your friends run their own (or use `matrix.org`'s free one), and your servers talk to each other; you all sit in shared rooms regardless of which server you're on.

## Why Conduit, not Synapse

Synapse is the reference implementation (Python + Postgres + Redis + ~1 GB RAM minimum). Conduit is a Rust reimplementation: single binary, embedded database (RocksDB), ~50 MB RAM. For a personal + small-circle homeserver, Conduit is dramatically less work.

If you ever need features Conduit lacks (server-side push notifications via UnifiedPush, multi-worker scaling, very complex room admin), you can switch to Synapse and your federation reputation stays — room state lives in *other* servers, not yours.

## ⚠️ One thing you can't change later

`SERVER_NAME` is permanent after first start. It's the domain part of every account on your server (`@you:<server_name>`). Conventions:

- **Use your bare domain** (`yourdomain.com`) so handles look short: `@you:yourdomain.com`.
- **Don't use a subdomain** like `matrix.yourdomain.com` unless you really want `@you:matrix.yourdomain.com` everywhere.

The *server itself* still lives on `matrix.yourdomain.com` (or wherever) — the `.well-known` files below tell other Matrix servers where to actually find it.

## Prerequisites

- Docker + Compose — see `../docker/`.
- A domain managed in Cloudflare (or wherever) — you need to publish two small JSON files at the bare domain.
- Cloudflare Tunnel running — see `../cloudflared/`.

## Setup walkthrough

### 1. Generate the registration token

```bash
openssl rand -base64 24
```

Paste into `.env` as `REGISTRATION_TOKEN`. Anyone with this string can register on your server, so treat it like a shared invite code.

### 2. Set `SERVER_NAME` in `.env`

```
SERVER_NAME=yourdomain.com
```

Bare domain. This is the one decision that's irreversible later.

### 3. Cloudflare Tunnel route

In Zero Trust → your tunnel → **Public Hostname** → **Add**:

| Subdomain | Domain | Service type | URL |
|-----------|--------|--------------|-----|
| `matrix` | `yourdomain.com` | HTTP | `host.docker.internal:8448` |

Save. This is where Matrix clients connect.

### 4. Bring it up

```bash
cp .env.example .env
nano .env             # edit SERVER_NAME and REGISTRATION_TOKEN
docker compose up -d
docker compose logs -f conduit
```

Wait for `conduit is ready` or similar.

### 5. Publish the two `.well-known` files

Other servers (matrix.org, your friends' homeservers) discover yours by reading two specific URLs at the *bare* `SERVER_NAME`. Both are static JSON.

You need to serve these at:

| URL | Contents |
|-----|----------|
| `https://yourdomain.com/.well-known/matrix/server` | `{"m.server": "matrix.yourdomain.com:443"}` |
| `https://yourdomain.com/.well-known/matrix/client` | `{"m.homeserver": {"base_url": "https://matrix.yourdomain.com"}}` |

Three ways to do this — pick whichever fits your setup:

**A. Cloudflare Workers (recommended — zero servers needed)**

In Cloudflare dashboard → Workers & Pages → Create Worker. Paste:

```js
export default {
  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/.well-known/matrix/server") {
      return new Response(JSON.stringify({"m.server": "matrix.yourdomain.com:443"}),
        { headers: {"Content-Type": "application/json"}});
    }
    if (url.pathname === "/.well-known/matrix/client") {
      return new Response(JSON.stringify({"m.homeserver": {"base_url": "https://matrix.yourdomain.com"}}),
        { headers: {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"}});
    }
    return new Response("not found", { status: 404 });
  }
}
```

Add a route on the worker: `yourdomain.com/.well-known/matrix/*` → this worker. Save.

**B. Cloudflare Pages / a redirect**
If you have an existing site at `yourdomain.com`, drop the two JSON files into its `public/.well-known/matrix/` directory and redeploy.

**C. Add the bare domain to the tunnel**
Add another tunnel route for `yourdomain.com` pointing at an HTTP server serving the two files. More moving parts than option A.

### 6. Verify federation works

The matrix.org federation tester:

```
https://federationtester.matrix.org/
```

Enter your `SERVER_NAME`. Every check should be green. If a check fails:
- "Well-known server" red → `/.well-known/matrix/server` not served correctly (test with `curl https://yourdomain.com/.well-known/matrix/server` — must return the JSON above)
- "Connection" red → tunnel route wrong, or Conduit not running
- "Valid certificates" red → Cloudflare-managed TLS should handle this; check the tunnel cert is healthy

### 7. Create your account

In a browser, go to https://app.element.io. Click **Edit** next to homeserver, set `https://matrix.yourdomain.com`. Then **Create account**. Use your registration token from `.env` when prompted.

Pick a strong password — this is your Matrix identity, lose it and you lose all chat history that wasn't backed up.

### 8. Set up cross-signing / key backup

In Element → **Settings → Security & Privacy → Cross-signing → Set up**. Set a security key (or passphrase). Without this, an end-to-end encrypted room becomes unreadable if you log out / lose your device.

### 9. Invite friends

Share the `REGISTRATION_TOKEN` with each friend you want on your server, plus the homeserver URL `https://matrix.yourdomain.com`. They follow the same step 7.

If you'd rather not run multiple accounts here, your friends can stay on their existing homeservers — Matrix federates fully, you DM each other by Matrix ID (`@friend:matrix.org`).

After your friends are on, set `ALLOW_REGISTRATION=false` in `.env` and `docker compose up -d` to stop further signups.

## Day-to-day commands

```bash
docker compose logs -f conduit            # live federation chatter + errors
docker compose ps                         # is it healthy?
docker compose pull && docker compose up -d   # upgrade — read release notes first
docker compose down                       # stop, keep history
docker compose down -v                    # ALSO wipes ALL rooms, history, accounts
```

`down -v` is destructive. The full chat history of every room your server has joined lives in that volume. Other servers in the same federation will still have their own copies, but yours is gone.

## Clients

Matrix has many clients. Pick one or several:

| Client | Platform | Best for |
|--------|----------|----------|
| **Element** | Web, iOS, Android, desktop | Default — feature-complete, official |
| **Element X** | iOS, Android | Newer, faster Element rewrite |
| **Cinny** | Web | Lighter, cleaner UI |
| **FluffyChat** | iOS, Android, desktop | Friendlier UI |
| **`gomuks`** | Terminal | Power users |

Point any of them at `https://matrix.yourdomain.com` and log in with your account.

## Federation hygiene

Once federated, your server will be contacted by every Matrix server hosting a room you've joined. You'll see a lot of traffic in `docker compose logs conduit` — that's normal, it's federation working.

**To delete a room from your server's storage** (you're the only one leaving, the room continues elsewhere): `/leave` in the client, then in the next major Conduit release you can purge the local state.

**To block another server** (spam, harassment): not supported in Conduit yet — needs a future release or Synapse for full server ACLs.

**To go offline temporarily**: just `docker compose down`. Federation handles outages — other servers retry. When you come back online, you'll catch up on missed events.

## Backups

The `conduit-data` named volume contains *everything*: accounts, rooms, history, encryption keys.

Standard NAS rsync of `/var/lib/docker/volumes/` (see `../backups/`) covers it. RocksDB doesn't have a `pg_dump` equivalent — for clean snapshots, stop Conduit briefly:

```bash
docker compose stop conduit
# rsync runs here from the NAS
docker compose start conduit
```

The `snapshot.sh` script in `../backups/README.md` already handles this pattern if you add the matrix stack to its STACKS list.

## Security posture

| Mitigation | Why |
|------------|-----|
| Pinned image tag | No silent upgrades; Conduit pre-1.0, breaking changes happen |
| `REGISTRATION_TOKEN` required | Stops drive-by signups on a public homeserver |
| Federation toggle | Can isolate the server if needed |
| End-to-end encryption | Off by default in a public room, ON by default for DMs and private rooms — set up cross-signing in step 8 |
| Cloudflare Tunnel | No public IP / port forwarding |
| Own docker network | Conduit can't reach other stacks |

## Troubleshooting

**Federation tester says "Well-known server: 404"**
The `/.well-known/matrix/server` file isn't being served at the bare domain. Test with `curl -v https://yourdomain.com/.well-known/matrix/server`. Check the Cloudflare Worker route applied, or that the file exists on whatever serves the bare domain.

**Login fails in Element with "Server is not aware of this room version"**
You're trying to join a room that uses a newer room version than Conduit supports. Update Conduit or use a different room.

**Friends on matrix.org can't message you**
Probably a .well-known issue. The federation tester is the source of truth — get every check green there first.

**Element says "Backup signing key" missing on second device login**
You skipped step 8 (cross-signing setup). Without that, encrypted rooms become unreadable on new devices. Set it up on a still-logged-in session before logging out.

**Logs show "Lost connection to" peers constantly**
Some Matrix servers have flaky federation. As long as the major ones (matrix.org, element.io) connect, the rest is acceptable noise.

**Want a bridge to Discord / Telegram / Signal**
Conduit doesn't support bridges (Matrix's appservice protocol isn't implemented yet). Either run a bridge against `matrix.org` instead, or migrate to Synapse if bridges are a must-have. The official bridge directory: https://matrix.org/ecosystem/bridges/

## Why this matters in the "Enterprise Learning" theme

Matrix is increasingly used inside large orgs (Element runs the platform for the German armed forces and the French government, for example) as an open-source Slack/Teams alternative. Running a homeserver teaches:

- **Federated identity** (server name vs user ID, distinct from email or social IDs)
- **`.well-known` discovery** (the same pattern modern protocols use for everything from OpenID Connect to Apple ATS)
- **End-to-end encryption with key backup** (cross-signing, megolm sessions, recovery keys)
- **Federation operations** (server outage handling, eventual consistency between independent stores)

Worth running for those alone, even if your friends were all happy on Discord.
