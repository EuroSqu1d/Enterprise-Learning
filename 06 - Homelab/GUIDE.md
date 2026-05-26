# Homelab — Beginner's Guide

Read this first. It explains *what* each piece is, *why* it's there, and *how* to bring it all up — assuming nothing.

The other README files in this section are reference docs (the "manual"). This file is the tutorial.

---

## 1. What you're building

You're going to run six small programs on one Linux box. Together they let you:

- See live graphs of how your server is doing (CPU, RAM, disk, network)
- See live graphs of every Docker container running on it
- Search through every log line every container produces — from one web UI
- Get alerts later, when you decide to add them

Here's the shape of it:

```
                 ┌────────────────┐
                 │    Grafana     │   ← you open this in a browser
                 │  (dashboards)  │     (port 3000)
                 └───────┬────────┘
                         │ asks for data
        ┌────────────────┼────────────────┐
        ▼                                 ▼
 ┌─────────────┐                   ┌─────────────┐
 │ Prometheus  │                   │    Loki     │
 │  (metrics   │                   │   (logs     │
 │   storage)  │                   │   storage)  │
 └──────┬──────┘                   └──────▲──────┘
        │ pulls metrics from              │ pushes logs to
        │                                 │
   ┌────┴─────┬──────────┐         ┌──────┴───────┐
   ▼          ▼          ▼         │   Promtail   │
┌─────────┐ ┌──────┐ ┌────────┐    │ (log shipper)│
│  node   │ │cAdvi-│ │... any │    └──────┬───────┘
│exporter │ │ sor  │ │ app's  │           │ reads
│(host    │ │(cont-│ │/metrics│           ▼
│metrics) │ │ainer)│ │endpoint│       host log files
└─────────┘ └──────┘ └────────┘       /var/log/*
                                   container log files
                                   /var/lib/docker/...
```

You don't install any of this directly on the server. Each box above is a **Docker container** — a small isolated process. Docker keeps them apart from each other and from the host OS.

---

## 2. The vocabulary (in plain English)

Skim this. Come back to it when a word later doesn't make sense.

- **Docker** — software that runs other software in isolated boxes called containers. The host can't easily reach into a container; a container can't easily reach into the host.
- **Container** — one running instance of a program in its own isolated box. Stop it and it's gone; start it again and it comes back fresh (except for data you saved in a *volume*).
- **Image** — the read-only template a container is launched from. Like a recipe. `grafana/grafana-oss:11.2.0` is an image. Run it and you get a Grafana container.
- **Tag** — the version pinned to an image. `:11.2.0` is a tag. `:latest` is also a tag but a bad idea because it silently changes.
- **Volume** — a named bit of disk space Docker manages outside the container, so data survives container restarts. Prometheus's database lives in a volume called `prometheus-data`.
- **Compose / `docker-compose.yml`** — a YAML file that describes a *group* of containers and how they connect. One `docker compose up -d` brings them all up together.
- **Network (docker)** — a virtual switch Docker creates so containers can find each other by name. We use one called `monitoring` so e.g. Grafana can reach Prometheus by typing `http://prometheus:9090`.
- **Metric** — a number with a timestamp. "CPU usage is 47% right now." Stored as a time series.
- **Log** — a line of text emitted by a program at a point in time. "User alice logged in at 14:02:11."
- **LogQL / PromQL** — query languages, one for logs, one for metrics. Same family. You don't need to memorise them; you'll mostly use templates.

---

## 3. The two halves of the stack

### Metrics side (numbers over time)

**Prometheus** is a database that's *very* good at storing numbers with timestamps. Every 15 seconds it goes around to every "exporter" and asks *"give me your current numbers"*. It writes those down. Months later you can ask *"what was CPU doing last Tuesday at 3am?"* and get an answer instantly.

**Node Exporter** runs on the host and exposes host metrics — CPU, RAM, disk, network, load average, etc. — at a URL Prometheus knows to scrape.

**cAdvisor** does the same thing but for Docker containers. It reads kernel counters to tell you how much CPU/RAM/network each individual container is using.

That's it. Three pieces. Prometheus scrapes the two exporters, holds the data, lets Grafana query it.

### Logs side (text lines)

**Loki** is to logs what Prometheus is to metrics. It stores log lines with timestamps and labels, and lets you search them later.

**Promtail** is the thing that *gets* logs into Loki. It tails files on the host:
- `/var/log/*.log` — system logs (auth, syslog, kernel)
- `/var/lib/docker/containers/*/*-json.log` — every container's stdout/stderr

It reads them, optionally rewrites them (e.g. scrubbing out secrets), then pushes them to Loki.

### The visualisation

**Grafana** is the dashboard tool you actually open in a browser. It's not a database — it queries Prometheus and Loki and draws graphs from the answers. Everything you'll *look at* lives in Grafana.

---

## 4. Why the code looks the way it does

A few choices in the files might look strange. Here's why they're there.

### Why pin every image tag?

Each image in `docker-compose.yml` has a specific version, like `prom/prometheus:v2.54.1`. Not `:latest`.

**Why:** `:latest` means "whatever's newest when I pull". That sounds fine until one morning Prometheus updates, its config format changes, and your stack won't start. Pinning means upgrades only happen when *you* edit the file. It's also a tiny security win — an attacker who swapped the image upstream can't get it onto your box silently.

**To upgrade later:** change the tag, run `docker compose pull && docker compose up -d`, see what breaks.

### Why is Loki not listed under "host ports"?

Open `docker-compose.yml`. The other services have a `ports:` block like:

```yaml
ports:
  - "3000:3000"     # host port : container port
```

`loki:` doesn't have one. That's deliberate. Loki is reachable only from *inside* the `monitoring` docker network — Grafana and Promtail can talk to it on `http://loki:3100`, but the host's port 3100 is closed. Less attack surface. You query logs *through* Grafana, never directly.

### Why is Promtail mounting host paths read-only (`:ro`)?

```yaml
volumes:
  - /var/log:/var/log:ro
  - /var/lib/docker/containers:/var/lib/docker/containers:ro
```

Promtail needs to *read* these to ship the logs. It doesn't need to *write* anything to them. `:ro` (read-only) means even if Promtail were ever compromised, it can't modify or delete logs, plant files, or otherwise damage the host. Cheap insurance.

### Why no docker.sock for Promtail?

Many tutorials mount `/var/run/docker.sock` into log shippers so they can ask Docker *"what containers exist?"*. The catch: that socket is root-equivalent. Anything that can write to it can launch a privileged container and own the host. We skip it.

The trade-off is Promtail would only see container *IDs*, not human-readable names. We fix that another way: in `docker/daemon.json` we set Docker itself to write a `tag` into every log line that includes the container name:

```json
"log-opts": { "tag": "{{.ImageName}}/{{.Name}}/{{.ID}}" }
```

Then Promtail's pipeline (in `promtail/promtail-config.yaml`) parses that tag and uses it as a label. You get pretty names *and* the docker socket stays untouched.

### Why scrub secrets in Promtail?

In `promtail/promtail-config.yaml` you'll see these blocks:

```yaml
- replace:
    expression: 'Bearer [A-Za-z0-9._\-]+'
    replace: 'Bearer [REDACTED]'
```

Apps misbehave. They log things they shouldn't — API keys, JWTs, the odd password. Once that lands in Loki, it sits there for 30 days and anyone with Grafana access can `grep` for it. The `replace` stages run *before* the line is stored, so the secret never reaches disk.

You can add more patterns: GitHub tokens (`ghp_…`), Slack tokens (`xoxb-…`), Stripe keys, whatever you actually use.

### Why is `GF_SECURITY_ADMIN_PASSWORD:?` written with a `?`

In `docker-compose.yml`:

```yaml
GF_SECURITY_ADMIN_PASSWORD: ${GF_SECURITY_ADMIN_PASSWORD:?set in .env}
```

The `:?` tells Compose *"refuse to start if this variable is empty"*. It's a guard against accidentally running Grafana with no password set. If you forget to fill in `.env`, you get a loud error instead of a quiet `admin/admin`.

---

## 5. Walkthrough: bringing it up for the first time

Assume a fresh Ubuntu or Debian server. You have SSH access. You've cloned this repo into your home directory.

### Step 1 — Install Docker

```bash
cd ~/Enterprise-Learning/"06 - Homelab"/docker
sudo ./install.sh
```

What this does, in plain English:
1. Checks you're on Ubuntu or Debian.
2. Removes any old/conflicting Docker packages.
3. Adds Docker's official package repository (so you get updates from Docker, not your distro's older fork).
4. Installs Docker Engine, the CLI, containerd, and the Compose plugin.
5. Writes `/etc/docker/daemon.json` with sensible defaults: log files rotate at 10 MB × 3 (so a runaway container can't fill your disk), and every container's logs get tagged with `image/name/id`.
6. Starts the Docker service and sets it to run on boot.

Verify:
```bash
docker --version          # should print a version number
docker compose version    # should also print one
```

### Step 2 — Let yourself run Docker without sudo

```bash
./post-install.sh
```

This adds your user to the `docker` group. **Then log out and back in** (or run `newgrp docker` in your current shell). Test:

```bash
docker run --rm hello-world
```

If you see "Hello from Docker!", you're good.

### Step 3 — Set up the monitoring stack

```bash
cd ../monitoring
cp .env.example .env
nano .env
```

In `nano`, change `GF_SECURITY_ADMIN_PASSWORD=changeme` to a real password you'll remember. Save (`Ctrl+O`, `Enter`) and exit (`Ctrl+X`).

### Step 4 — Bring it all up

```bash
docker compose up -d
```

`up` means "start them", `-d` means "in the background". First time, Docker downloads six images (~500 MB total). After a minute, check what's running:

```bash
docker compose ps
```

You should see six services with status `Up` or `Up (healthy)`.

### Step 5 — Open Grafana

In your browser go to `http://<your-server-ip>:3000`. Log in:
- Username: `admin`
- Password: whatever you set in `.env`

Grafana skips the "set a new password" prompt because you set one via env. You're in.

### Step 6 — Verify everything is connected

In Grafana's left sidebar, go to **Connections → Data sources**. You should see:
- **Prometheus** (default) — click it, scroll down, press **Save & test**. Green tick means Grafana can reach Prometheus.
- **Loki** — same drill. Green tick means logs are flowing.

Then open `http://<your-server-ip>:9090` in another tab — that's Prometheus directly. Go to **Status → Targets**. You should see five jobs (prometheus, node-exporter, cadvisor, loki, promtail) all marked **UP**. If any is **DOWN**, that service didn't start cleanly — see the troubleshooting section.

### Step 7 — Add your first dashboard

Back in Grafana:
1. Left sidebar → **Dashboards** → **New** → **Import**.
2. In "Import via grafana.com" type `1860` and click **Load**.
3. On the next screen, pick **Prometheus** as the data source and click **Import**.

You should now be staring at "Node Exporter Full" — about 200 panels showing every conceivable host metric. Welcome to the rabbit hole.

Repeat with these IDs:
- `14282` — cAdvisor (per-container metrics)
- `13639` — Loki logs overview

### Step 8 — Search some logs

Left sidebar → **Explore** → switch the datasource dropdown (top of page) from Prometheus to **Loki**.

In the query box paste:

```
{job="docker"}
```

Click **Run query**. You'll see every log line every container has emitted since startup. Now try:

```
{container="grafana"}
```

That's just Grafana's own logs. Or:

```
{job="varlogs"} |= "Failed password"
```

That searches the host's `/var/log` for failed SSH login attempts.

You now have a real homelab observability stack.

---

## 6. Daily-driver commands

```bash
# See what's running and whether anything restarted
docker compose ps

# Watch a container's logs live
docker compose logs -f grafana

# Restart one service after changing its config file
docker compose restart prometheus

# Pull newer image versions (after bumping tags in docker-compose.yml)
docker compose pull
docker compose up -d

# Stop everything (data stays in volumes)
docker compose down

# Stop everything AND delete the data (start from scratch)
docker compose down -v
```

All of these must be run from inside `06 - Homelab/monitoring/` because that's where `docker-compose.yml` lives.

---

## 7. When something doesn't work

**`docker compose up -d` fails immediately with "GF_SECURITY_ADMIN_PASSWORD is required"**
You didn't create `.env` or didn't set the password. Run `cp .env.example .env` and edit it.

**Prometheus targets page shows a target as DOWN**
That service's container probably crashed. Run `docker compose ps` to find which one, then `docker compose logs <service>` to read its error output. 90% of the time it's a typo in a config file.

**Grafana login fails**
Check `.env` — the password is whatever you set there. If you forgot, `docker compose down -v && docker compose up -d` will reset everything (including dashboards).

**Loki target is UP but no logs appear in Grafana**
Promtail isn't reading. Run `docker compose logs promtail` — usually a permissions issue on `/var/log` or `/var/lib/docker/containers`.

**"I changed prometheus.yml and nothing happened"**
Prometheus reads the config once at startup. Either `docker compose restart prometheus` or, if you don't want to interrupt scraping, `curl -X POST http://localhost:9090/-/reload`.

**Disk filling up**
The `prometheus-data` and `loki-data` named volumes grow over time. Retention is 30 days. If you want less, edit:
- `monitoring/docker-compose.yml` → `--storage.tsdb.retention.time=30d` (Prometheus)
- `monitoring/loki/loki-config.yaml` → `retention_period: 720h` (Loki)

---

## 8. Where to go next

Once this stack is comfortable, the natural additions are:

- **Reverse proxy + HTTPS** — Traefik or Caddy in front of Grafana so you can reach it on `grafana.yourdomain` with a real cert. Right now it's HTTP only, fine on a LAN.
- **Alerting** — Prometheus has Alertmanager. Configure it to ping you on Discord / Slack / email when CPU pegs or a container dies.
- **More exporters** — there's a `prom/blackbox-exporter` (HTTP/TCP/ICMP probes), `nginx-prometheus-exporter`, exporters for every database. Drop one in, add a job to `prometheus.yml`, restart Prometheus.
- **Backups** — back up the docker volumes (`/var/lib/docker/volumes/prometheus-data/_data` etc.) somewhere off this host.

Each of those becomes its own subdirectory under `06 - Homelab/` following the same convention.

---

## 9. Why this lives in one folder, not five repos

The whole `06 - Homelab/` section is one *project*. Splitting it into separate repos (one for Docker, one for monitoring, one for the future reverse proxy…) would mean cloning five things, keeping them in sync, and remembering which one configures what. A single folder with one subdirectory per service is easier to navigate, easier to back up, and easier to come back to in six months when you've forgotten how it all fits together. That last bit is the real reason — Future You is the main user of this guide.
