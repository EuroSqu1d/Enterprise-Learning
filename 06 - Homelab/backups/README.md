# Backups

Your NAS pulls snapshots of the homelab. Nothing runs on the homelab side except SSH (already there). This folder documents the pattern so you can rebuild it after a wipe.

## What gets backed up

| Path on homelab host | What's in it | Critical? |
|----------------------|--------------|-----------|
| `/var/lib/docker/volumes/` | All named volumes — Grafana DB, Prometheus TSDB, Loki chunks, Jellyfin config + cache, Alertmanager state | **Yes** |
| `~/Enterprise-Learning/` | Compose files, env templates, this repo | Already in git, skip |
| `/etc/docker/daemon.json` | Docker log-rotation + tag config | Cheap to recreate, skip |

The compose files + this repo live in git already, so you only need to back up the docker volumes. Restoring is "fresh OS install → run docker installer → restore volumes from NAS → `docker compose up -d`".

## The command (run from the NAS)

This is what your NAS cron should execute. SSH key auth assumed.

```bash
rsync -aAXH --delete --info=progress2 \
  -e 'ssh -i /volume1/keys/homelab-backup -o StrictHostKeyChecking=accept-new' \
  root@<homelab-host>:/var/lib/docker/volumes/ \
  /volume1/backups/homelab-volumes/
```

Flags explained:
- `-a` — archive mode (preserves permissions, symlinks, times, etc.)
- `-A -X -H` — preserve ACLs, xattrs, hardlinks (needed for some apps)
- `--delete` — remove files on the NAS that no longer exist on the homelab (true mirror)
- `--info=progress2` — overall progress, not per-file (less log noise)
- `-e 'ssh -i …'` — use a specific SSH key, not the NAS's default

## Server-side setup (one-off)

On the homelab host:

```bash
# Generate a key pair on the NAS first, then on the homelab:
sudo mkdir -p /root/.ssh
sudo nano /root/.ssh/authorized_keys     # paste the NAS's public key
sudo chmod 600 /root/.ssh/authorized_keys
```

That's it. No agent, no service. If you'd rather not allow root SSH, create a dedicated `backup` user and grant sudo-only access to `rsync` — see the optional script below.

## Why root? (and how to avoid it)

`/var/lib/docker/volumes/` is owned by root. Easiest path is rsync-as-root over SSH.

If you want least-privilege:

1. Create a `backup` user on the homelab.
2. Add this to `/etc/sudoers.d/backup`:
   ```
   backup ALL=(root) NOPASSWD: /usr/bin/rsync --server *
   ```
3. NAS command becomes:
   ```bash
   rsync -aAXH --delete --rsync-path="sudo rsync" -e 'ssh -i ...' \
     backup@<host>:/var/lib/docker/volumes/ /volume1/backups/homelab-volumes/
   ```

## Consistency caveat

A plain `rsync` of a live database directory can capture a half-written state. For homelab volumes this means:

- **Prometheus** — usually replays its WAL on restart; worst case you lose a few minutes of metrics. Fine.
- **Loki** — same story; resilient.
- **Grafana** — SQLite; theoretically corruptable but in practice safe for low-write workloads.
- **Jellyfin** — SQLite database; same caveat.

For *near-zero* risk, run `snapshot.sh` (below) **on the homelab side** before the NAS pulls. It stops each stack, lets rsync run, then starts them again — ~30 seconds of downtime per run.

## Optional: `snapshot.sh` (run on homelab before NAS pull)

Save this in `/usr/local/bin/snapshot.sh` and `chmod +x`:

```bash
#!/usr/bin/env bash
# Quiesce stacks so the NAS can pull a clean snapshot.
set -euo pipefail

STACKS=(
  "$HOME/Enterprise-Learning/06 - Homelab/monitoring"
  "$HOME/Enterprise-Learning/06 - Homelab/jellyfin"
)

for dir in "${STACKS[@]}"; do
  echo ">>> Stopping $dir"
  (cd "$dir" && docker compose stop)
done

# Hold here until the NAS finishes. Simplest: sleep long enough for the
# pull (NAS rsync usually <2 min for small homelabs). Better: NAS calls
# this script + the rsync over SSH itself.
sleep 120

for dir in "${STACKS[@]}"; do
  echo ">>> Starting $dir"
  (cd "$dir" && docker compose up -d)
done
```

Wire it so the NAS runs the script over SSH before rsyncing, e.g.:

```bash
ssh root@<homelab> /usr/local/bin/snapshot.sh &
sleep 10   # give containers time to stop
rsync ... # as above
```

Or skip this entirely and accept the small consistency risk — for a single-user homelab where Prometheus losing 3 minutes of CPU samples isn't a big deal, plain rsync is fine.

## Restore

After a wipe / fresh install:

```bash
# 1. Reinstall Docker on the new host
sudo ~/Enterprise-Learning/"06 - Homelab"/docker/install.sh

# 2. Stop docker so files in /var/lib/docker/volumes are quiescent
sudo systemctl stop docker

# 3. Pull the backup back (run from the homelab, or push from NAS)
sudo rsync -aAXH --delete /volume1/backups/homelab-volumes/ /var/lib/docker/volumes/

# 4. Start docker and bring stacks up
sudo systemctl start docker
cd ~/Enterprise-Learning/"06 - Homelab"/monitoring && docker compose up -d
cd ~/Enterprise-Learning/"06 - Homelab"/jellyfin   && docker compose up -d
# ...etc.
```

Dashboards, watch history, log retention all come back exactly as they were.

## Test the restore

Untested backups aren't backups. Once a quarter:

1. Spin up a throwaway VM or use the second Proxmox host.
2. Restore the latest snapshot there.
3. Bring up `monitoring/` and confirm Grafana shows historical data.
4. Tear it down.

If that's too much friction, at the very least open the NAS occasionally and confirm yesterday's snapshot exists and has a sensible size.
