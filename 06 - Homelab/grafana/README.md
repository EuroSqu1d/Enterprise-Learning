# Grafana

Grafana OSS running in Docker, with a named volume for persistence.

## Prerequisites

Docker Engine + Compose plugin installed — see `../docker/`.

## Run

```bash
cp .env.example .env
# edit .env to set GF_SECURITY_ADMIN_PASSWORD
docker compose up -d
```

Grafana will be available on `http://<host>:3000`. Default user is `admin`; the initial password comes from `.env`.

## Update

```bash
docker compose pull
docker compose up -d
```

## Data

Dashboards, datasources, and the SQLite DB live in the `grafana-data` named volume. Back it up before destroying the stack.
