# NGO Management System — Reproducible VPS Docker Deployment Guide

This guide describes how to deploy, operate, back up, and update the NGO Management System PostgreSQL 16 database and Node.js + TypeScript + Fastify backend API on our company VPS using Docker Compose.

---

## 1. Architecture & Persistence Overview

```
[ Flutter Desktop Clients (Windows) ]
                 │
                 ▼ HTTPS (Port 443 / Reverse Proxy)
     [ Host VPS / Nginx or Caddy ]
                 │
                 ▼ HTTP (127.0.0.1:8080)
     [ Backend Container: ngo-backend (Node.js 22 / Fastify) ]
                 │
                 ▼ Private Docker Bridge Network ('ngo-network')
     [ Database Container: ngo-postgres (PostgreSQL 16 - Port 5432 Internal Only) ]
                 │
                 ▼ Mounted at /var/lib/postgresql/data (PGDATA=/var/lib/postgresql/data/pgdata)
     [ Persistent Docker Named Volume ('ngo-pgdata') ]
```

### Security & Persistence Guardrails
- **PostgreSQL port `5432` is NOT published to the host or public internet.** Database access is restricted exclusively to containers attached to the private `ngo-network` bridge.
- **Persistent Named Volume (`ngo-pgdata`)**: All PostgreSQL data files reside in the external Docker volume `ngo-pgdata` (`PGDATA=/var/lib/postgresql/data/pgdata`), never inside the backend image or the PostgreSQL container's disposable filesystem. Data survives normal container restarts (`docker compose restart`), container recreation (`docker compose up -d --force-recreate`), and backend image updates (`docker compose up -d --build`).
- **Automatic Schema Initialization**: On every startup, `ngo-backend` waits for `ngo-postgres` to pass its `pg_isready` health check, runs `node dist/db/migrate.js up` (`node-pg-migrate` tracking history in `public.pgmigrations`), and only then launches Fastify (`node dist/server.js`). The backend's `/ready` health check verifies live PostgreSQL connectivity before marking `ngo-backend` healthy.
- **Non-Root Runtime**: The backend production container runs as the unprivileged `node` user.
- **No Committed Secrets or Data**: Never commit `.env`, database dumps (`*.dump`, `*.sql.gz`), or Firebase exports into Git. A fresh repository clone starts with an empty PostgreSQL database and automatically initializes the full 17-table schema (`+ pgmigrations`).

> **CRITICAL SAFETY RULE:**
> **NEVER run `docker compose down -v` in production or routine maintenance.** The `-v` flag deletes named volumes, which will destroy the `ngo-pgdata` database volume. Use `docker compose stop`, `docker compose restart`, or `docker compose down` (without `-v`) when stopping containers.

---

## 2. VPS Prerequisites

- Linux VPS (Ubuntu 22.04 LTS / 24.04 LTS or Debian 12 recommended)
- Docker Engine (`>= 24.0`)
- Docker Compose plugin (`>= 2.20`)
- Git and OpenSSL (`openssl`)

---

## 3. Initial VPS Deployment Procedure

### Step 1: Clone the Repository
```bash
git clone https://github.com/your-org/NGO.git /opt/ngo
cd /opt/ngo
```

### Step 2: Create the Production `.env` File & Configure Strong Secrets
```bash
cp .env.example .env
chmod 600 .env
```

Generate a strong, unique password for `POSTGRES_PASSWORD` (at least 32 random bytes):
```bash
openssl rand -hex 32
```

Edit `/opt/ngo/.env` and set your production values:
```dotenv
POSTGRES_DB=ngo_db
POSTGRES_USER=ngo_user
POSTGRES_PASSWORD=<paste-output-of-openssl-rand-hex-32>
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

PORT=8080
HOST=0.0.0.0
NODE_ENV=production
LOG_LEVEL=info
# Leave blank for native desktop-only deployment, or provide comma-separated approved browser origins.
# Wildcard '*' is strictly prohibited.
CORS_ORIGINS=""

FIREBASE_PROJECT_ID=ngo-management-system-new-as
```
*(Note: Production startup automatically rejects default/placeholder passwords such as `replace_with_secure_password_in_production`, `ngo_password`, or `NGO@2026`.)*

### Step 3: Validate Compose Configuration & Pull PostgreSQL 16
```bash
docker compose config
docker compose pull postgres
```

### Step 4: Build & Start the Stack
```bash
docker compose up -d --build
```

This executes the deterministic startup sequence:
1. `ngo-postgres` starts and initializes `/var/lib/postgresql/data/pgdata` on the `ngo-pgdata` volume if empty.
2. `ngo-postgres` passes its `pg_isready` health check.
3. `ngo-backend` runs pending SQL migrations (`001_initial_schema` through `005_firebase_uid_width`) via `node dist/db/migrate.js up`.
4. `ngo-backend` starts Fastify on port `8080` and passes its `/ready` health check.

### Step 5: Verify Container Status, Logs & Readiness
```bash
# Check container states (both should report 'healthy')
docker compose ps

# Follow backend startup and migration logs
docker compose logs -f backend

# Follow PostgreSQL logs
docker compose logs -f postgres
```

Verify HTTP health and database readiness endpoints from the VPS host:
```bash
curl -fsS http://localhost:8080/health
curl -fsS http://localhost:8080/ready
```

---

## 4. Verifying & Applying Database Migrations

Migrations are applied automatically whenever `ngo-backend` starts. You can also inspect or trigger migrations manually at any time:

```bash
# Check applied, pending, and unexpected migrations (returns JSON)
docker compose exec backend node dist/db/migrate.js status

# Explicitly apply any pending upward migrations
docker compose exec backend node dist/db/migrate.js up

# Inspect the pgmigrations tracking table and domain tables directly in PostgreSQL
docker compose exec postgres psql -U "${POSTGRES_USER:-ngo_user}" -d "${POSTGRES_DB:-ngo_db}" -c "\dt"
docker compose exec postgres psql -U "${POSTGRES_USER:-ngo_user}" -d "${POSTGRES_DB:-ngo_db}" -c "SELECT id, name, run_on FROM pgmigrations ORDER BY id;"
```

---

## 5. Updating the Application Without Deleting Persistent Data

To deploy new backend code or new database migrations on the VPS while preserving all existing PostgreSQL data in `ngo-pgdata`:

```bash
cd /opt/ngo

# 1. Take a pre-update backup (recommended)
mkdir -p /opt/ngo-backups
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-ngo_user}" -d "${POSTGRES_DB:-ngo_db}" | gzip > "/opt/ngo-backups/pre_update_$(date +%Y%m%d_%H%M%S).sql.gz"

# 2. Pull the latest repository changes
git pull --ff-only

# 3. Rebuild and recreate only updated containers (ngo-pgdata volume is untouched)
docker compose up -d --build

# 4. Verify health and migration status
docker compose ps
docker compose exec backend node dist/db/migrate.js status
curl -fsS http://localhost:8080/ready
```

---

## 6. Database Backup & Restore Procedures

### Create a Compressed Backup
```bash
mkdir -p /opt/ngo-backups
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-ngo_user}" -d "${POSTGRES_DB:-ngo_db}" --clean --if-exists | gzip > "/opt/ngo-backups/ngo_db_$(date +%Y%m%d_%H%M%S).sql.gz"
```

### Restore from a Compressed Backup
```bash
# Verify the backup file exists before restoring
ls -lh /opt/ngo-backups/ngo_db_YYYYMMDD_HHMMSS.sql.gz

# Stream the backup into PostgreSQL
gunzip -c /opt/ngo-backups/ngo_db_YYYYMMDD_HHMMSS.sql.gz | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-ngo_user}" -d "${POSTGRES_DB:-ngo_db}"
```

---

## 7. Deliberate Firebase RTDB Data Import (Separate Cutover Step)

A fresh Docker Compose deployment intentionally creates an **empty** database with the required schema. Importing historical Firebase Realtime Database records is a separate, deliberate operator step executed only during planned migration testing or cutover:

```bash
# Dry-run validation and reconciliation report (no database writes)
cd /opt/ngo/backend
npm run import:firebase -- --file /path/to/firebase-export.json --dry-run

# Live idempotent import into PostgreSQL
npm run import:firebase -- --file /path/to/firebase-export.json --report /opt/ngo-backups/import-report.json
```

---

## 8. Reverse Proxy & TLS Configuration (Nginx Example)

Bind port `8080` behind Nginx or Caddy with TLS termination:

```nginx
server {
    listen 80;
    server_name api.ngo.yourdomain.org;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.ngo.yourdomain.org;

    ssl_certificate     /etc/letsencrypt/live/api.ngo.yourdomain.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.ngo.yourdomain.org/privkey.pem;

    client_max_body_size 20M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
    }
}
```
