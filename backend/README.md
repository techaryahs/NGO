# NGO Management System — Backend API

Fastify/PostgreSQL backend under migration. **Production cutover is blocked.** The Flutter domain services still use Firebase; enabling the PostgreSQL feature flag now fails explicitly. See [the independent audit](../audit/independent-backend-audit.md) for the endpoint matrix, runtime evidence, corrected defects and remaining gaps.

---

## 1. Architecture & Technology Stack

- **Runtime:** Node.js (LTS >= 20.x, built on Alpine)
- **Language:** TypeScript 5.x
- **HTTP Framework:** Fastify 4.x (high-throughput, low-overhead HTTP layer)
- **Database:** PostgreSQL 16 (relational authoritative store)
- **Database Driver:** `pg` (node-postgres with resilient connection pooling)
- **Schema Migration Tool:** `node-pg-migrate` (declarative, reversible SQL DDL migrations)
- **Request Validation & Config:** Zod (runtime type inference and validation)
- **Testing:** Vitest

---

## 2. Directory Structure

```
backend/
├── Dockerfile                   # Multi-stage production build (Alpine)
├── package.json                 # Dependency definitions and lifecycle scripts
├── tsconfig.json                # Strict TypeScript configuration
├── migrations/                  # Schema migration definitions
│   └── 001_initial_schema.sql  # Baseline DDL defining all 17 domain tables
├── src/
│   ├── app.ts                  # Fastify application factory & middleware
│   ├── server.ts               # Server entry point & graceful shutdown hooks
│   ├── config/
│   │   └── index.ts            # Zod-validated configuration & URL generator
│   ├── db/
│   │   ├── index.ts            # pg.Pool connection lifecycle & health query
│   │   └── migrate.ts          # Programmatic migration runner
│   └── routes/
│       └── health.ts           # /health and /ready probe handlers
└── tests/
    ├── config.test.ts          # Environment and URL validation tests
    └── health.test.ts          # Unit/integration probe tests (via app.inject)
```

---

## 3. Local Development Setup

### Prerequisites

- Node.js >= 20.0.0
- npm >= 10.0.0
- PostgreSQL 16 instance (or running Docker container)

### Setup Steps

1. **Install dependencies:**
   ```bash
   cd backend
   npm install
   ```

2. **Configure environment:**
   Create a `.env` file at the repository root or inside `backend/`:
   ```ini
   POSTGRES_HOST=localhost
   POSTGRES_PORT=5432
   POSTGRES_DB=ngo_db
   POSTGRES_USER=ngo_user
   POSTGRES_PASSWORD=your_secure_password
   PORT=8080
   NODE_ENV=development
   FIREBASE_PROJECT_ID=your_firebase_project_id
   ```

3. **Run database migrations:**
   ```bash
   npm run migrate:up
   ```

4. **Start the development server with live reload:**
   ```bash
   npm run dev
   ```

5. **Run automated test suite:**
   ```bash
   npm test
   ```
   This runs mocked/unit tests; real database suites require explicit opt-in and dedicated disposable databases. See the audit for exact commands and connection guards. Skipped database tests are not runtime evidence.

6. **Build production bundles:**
   ```bash
   npm run build
   ```

---

## 4. API Endpoints

### Liveness Probe
- **`GET /health`** (also mapped to `/api/health`)
- Returns `200 OK` with uptime and service metadata.
- Used by orchestrators and load balancers to verify the process is alive.

### Readiness Probe
- **`GET /ready`** (also mapped to `/api/ready`)
- Executes a low-latency `SELECT 1` ping against PostgreSQL.
- Returns `200 OK` with `{ "status": "ready", "database": "connected", "latencyMs": 2 }` if reachable.
- Returns `503 Service Unavailable` with a safe generic message if the database pool cannot establish a connection.

---

## 5. Migration Management

Schema migrations are tracked in the `pgmigrations` table:

- **Apply all pending migrations:**
  ```bash
  npm run migrate:up
  ```
- **Inspect applied and pending migrations:**
  ```bash
  npm run migrate:status
  ```
- **Rollback the last migration, only in an explicitly enabled disposable local test database:**
  ```bash
  npm run migrate:down
  ```
  Requires `NODE_ENV=test`, `ALLOW_DISPOSABLE_DB_ROLLBACK=1`, loopback host and an `ngo_audit_*` database. Never use rollback as a production deployment step. Widened UID/photo columns intentionally remain wide during rollback to preserve valid values.
- **Generate a new migration:**
  ```bash
  npm run migrate:create <migration_name>
  ```

The container runs compiled migrations on every startup before launching the API, so initialized databases receive upgrades. A conflicting legacy record causes migration failure instead of silent history deletion. Container build/start/restart still requires validation with an available Docker daemon.

## Firebase import

`npm run import:firebase -- <explicit-export.json>` defaults to dry-run. Committing requires `--apply`. Any rejected record or unsupported nonempty branch rolls the entire import back. The importer supports core collections, not every ERP/photo-store/settings branch; review the [importer audit](../audit/importer-audit.md) before staging migration. Never point an audit run at production.
