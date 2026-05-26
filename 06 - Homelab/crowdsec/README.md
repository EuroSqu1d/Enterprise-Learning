# CrowdSec

Behavioural IPS — reads logs, identifies attackers, blocks them at the Cloudflare edge so they never reach your homelab. Also subscribes you to a community blocklist of IPs other CrowdSec users have already caught.

| Service | Image | Host port | Purpose |
|---------|-------|-----------|---------|
| CrowdSec agent | `crowdsecurity/crowdsec:v1.6.3` | *not exposed* | Log parsing, scenario matching, decisions DB |
| CF bouncer | `crowdsecurity/cloudflare-bouncer:v0.3.1` | *not exposed* | Pushes blocked IPs into Cloudflare WAF |

## How it fits

```
attacker ──HTTP──► cloudflare edge ──tunnel──► your homelab apps
                       ▲                              │
                       │ blocks added                 │ logs
                       │ via API                      ▼
                  ┌────┴─────┐               /var/lib/docker/containers
                  │ CF       │◄──decisions── │   /var/log
                  │ bouncer  │               │
                  └──────────┘               │
                       ▲                     ▼
                       └────api──── crowdsec agent
                                    (scenarios + DB)
```

Attack hits an app → app logs it with the real client IP → CrowdSec agent matches a scenario → decision created → CF bouncer pushes that IP into Cloudflare's IP Access Rules → next request from that IP gets rejected at CF's edge.

## Prerequisites

- Docker + Compose — see `../docker/`.
- Cloudflare Tunnel running, with at least one site behind it — see `../cloudflared/`.
- Apps logging the real client IP. Already configured in our stacks:
  - `vaultwarden` — `IP_HEADER=CF-Connecting-IP` (set)
  - `grafana` — Grafana doesn't natively read CF headers; alerts on Grafana logins come from blackbox + Alertmanager instead.
  - `immich` — uses Express; reads `CF-Connecting-IP` automatically when behind a known proxy.

## Setup walkthrough

### 1. Initial start (no bouncer yet)

The bouncer won't work yet because we haven't generated its key. Bring up just the agent first:

```bash
cp .env.example .env
# Leave BOUNCER_KEY_CF / CF_* placeholders for now.
docker compose up -d crowdsec
docker compose logs -f crowdsec
```

Wait for `Starting processing data` and `bind to 0.0.0.0:8080`. The agent is now reading logs.

### 2. Check it's seeing things

```bash
docker compose exec crowdsec cscli metrics
```

Under "Acquisition" you should see lines for `/var/log/auth.log`, `/var/log/syslog`, and `/var/lib/docker/containers/...` with non-zero `read` counts.

```bash
docker compose exec crowdsec cscli scenarios list
```

Shows the loaded scenarios. The `COLLECTIONS` env var in the compose file installed `crowdsecurity/linux`, `sshd`, `base-http-scenarios`, and `http-cve`.

### 3. (Optional) Enrol with the central console

Free dashboard showing your alerts + community visibility. Sign up at https://app.crowdsec.net, click *Add an instance*, copy the enrollment key, paste into `.env`:

```bash
nano .env       # set CROWDSEC_ENROLL_KEY=<paste>
docker compose up -d crowdsec
# Then go back to the CrowdSec dashboard and click "Validate" on the pending instance.
```

### 4. Generate the bouncer key

```bash
docker compose exec crowdsec cscli bouncers add cf-bouncer
```

Output looks like:

```
Api key for 'cf-bouncer':

   ab12cd34ef56gh78ij90kl12mn34op56...

Please keep this key since you will not be able to retrieve it!
```

Copy that key into `.env` as `BOUNCER_KEY_CF=...`.

### 5. Create the Cloudflare API token + grab zone IDs

In the CF dashboard:

a. **Get your zone IDs.** Open the overview page for each domain you want CrowdSec to protect. The Zone ID is in the right sidebar. Copy it.

b. **Create an API token** at https://dash.cloudflare.com/profile/api-tokens → **Create Token** → **Custom token**. Permissions:

   | Type | Resource | Permission |
   |------|----------|------------|
   | Account | Account Filter Lists | Edit |
   | Zone | Zone WAF | Edit |
   | Zone | Zone | Read |

   Account Resources: include the relevant account.
   Zone Resources: include only the specific zone(s) — never "All zones".

   Create it, copy the token (you won't be able to view it again).

c. Paste both into `.env`:

```
CF_API_TOKEN=<token>
CF_ZONE_IDS=<zone_id_1>,<zone_id_2>
```

### 6. Start the bouncer

```bash
docker compose up -d cf-bouncer
docker compose logs -f cf-bouncer
```

Wait for `bouncer started successfully`. To verify the link is live:

```bash
docker compose exec crowdsec cscli bouncers list
```

`cf-bouncer` should show `valid: true` and a recent `last_pull`.

### 7. Test it (cautiously)

Add a fake decision against a junk IP and confirm Cloudflare picks it up:

```bash
docker compose exec crowdsec cscli decisions add --ip 203.0.113.42 --duration 5m --reason "test"
```

Watch the bouncer log:

```bash
docker compose logs -f cf-bouncer
```

Within ~10 seconds it should log `Adding new IP rules`. Then check the CF dashboard → your zone → **Security → WAF → Tools** — the IP should appear in the block list.

Wait 5 minutes (the decision's duration); CrowdSec automatically expires it and the bouncer removes it from CF.

**Don't test with your own IP** — you'll lock yourself out of your own services.

## Day-to-day commands

```bash
# Active decisions (currently blocked IPs)
docker compose exec crowdsec cscli decisions list

# Recent alerts (matched scenarios that haven't yet caused a block, or did)
docker compose exec crowdsec cscli alerts list

# Manually unblock an IP if you locked someone out by accident
docker compose exec crowdsec cscli decisions delete --ip 1.2.3.4

# Install another collection (e.g. for nginx attack patterns)
docker compose exec crowdsec cscli collections install crowdsecurity/nginx
docker compose restart crowdsec

# Update scenarios + community blocklist (auto-runs daily, this forces it)
docker compose exec crowdsec cscli hub update
docker compose exec crowdsec cscli hub upgrade
```

## Adding host-level SSH protection (optional)

The CF bouncer only blocks at Cloudflare. For SSH brute force on your homelab's *public IP* (separate from CF tunnel traffic), you want the firewall bouncer running on the host so it can edit iptables.

Cleanest install — on the host, NOT in docker:

```bash
sudo apt update
sudo apt install -y crowdsec-firewall-bouncer-iptables
sudo cscli bouncers add fw-bouncer-host
# Paste the key into /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
sudo systemctl restart crowdsec-firewall-bouncer
```

Wait — `cscli` on the host would need to reach the CrowdSec agent running in docker. Simplest: use the agent's bouncer-creation command from inside the container:

```bash
docker compose exec crowdsec cscli bouncers add fw-bouncer-host
```

Paste that key into the host's `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml` and point `api_url:` at `http://localhost:8080` *only after* you publish that port from the agent (add `ports: ["127.0.0.1:8080:8080"]` to the `crowdsec` service so the host can reach it without exposing publicly).

Reload and you've now got iptables-level SSH brute force protection feeding off the same agent.

## Backups

The `crowdsec-db` and `crowdsec-config` volumes contain your alert history, bouncer registrations, and any custom whitelists. Backed up by the NAS via `/var/lib/docker/volumes/` — see `../backups/`.

The CF bouncer state (`cf-bouncer-config`) is small but worth keeping; it tracks which rules in Cloudflare it owns so it won't trample anything you manually added.

## Security posture

| Mitigation | Why |
|------------|-----|
| Pinned image tags | No silent agent or bouncer updates |
| Agent LAPI not exposed to host | Only the bouncer (same docker network) reaches it |
| Read-only log mounts | Same as Promtail's posture — can't modify or delete logs |
| CF API token scoped to specific zones | Token loss can't affect other zones in your account |
| BOUNCER_KEY_CF + CF_API_TOKEN guarded with `:?` | Bouncer won't start with empty creds |
| Decisions blocked at CF edge, not your network | Cheaper, attacker never reaches your tunnel |
| Test command available before real-world test | Don't lock yourself out |

## What it catches (default scenarios)

A non-exhaustive sample of what the four installed collections detect:

- SSH brute force (>10 failed logins from one IP)
- SSH user enumeration
- HTTP CVE probing (Log4Shell, Spring4Shell etc.)
- HTTP path scanning (`.env`, `.git/config`, `wp-login.php`)
- HTTP bad user agents (scrapers / scanners)
- Sudo abuse on the host
- Generic crawler patterns

`cscli scenarios list` shows all of them. Add more with `cscli collections install <name>` after browsing https://hub.crowdsec.net.

## Troubleshooting

**`docker compose exec crowdsec cscli ...` fails: "no such container"**
Agent didn't start. `docker compose logs crowdsec` — usually a typo in a custom `acquis.d/` file.

**`metrics` shows zero acquisition reads**
Mount paths wrong or empty. Confirm `/var/log` has files and `/var/lib/docker/containers` is populated.

**CF bouncer logs: "Unauthorized" / "403"**
`CF_API_TOKEN` is wrong, expired, or missing one of the required scopes.

**CF bouncer logs: "no decisions"**
That's fine — it means nothing's being blocked right now. Use the test command in step 7 to confirm the wiring.

**You locked yourself out**
From a different network or via cellular:
```bash
docker compose exec crowdsec cscli decisions delete --ip <your-ip>
```
If you can't reach the homelab at all because the block is on a service you need to use first (uncommon — your home IP shouldn't be in attack scenarios), SSH to the host directly and remove the bouncer config to disable it, then sort it out.
