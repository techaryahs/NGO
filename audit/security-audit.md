# Authentication, security, and deployment audit

Audit date: 16 October 2026. Scope: actual repository source, Fastify injection with synthetic signed JWTs, mocked database/key fetches, configuration/deployment inspection. No GUI, live Firebase writes, production database operations, or cutover.

## Confirmed defects corrected

1. **Critical: arbitrary JWT impersonation.** `auth.ts` originally called `jwt.decode()` and never verified a signature, issuer, audience, or Google signing key. A fabricated unsigned token and a token signed by an attacker key were accepted. Replaced decoding-as-authentication with RS256 verification against the fixed Google public certificate endpoint, project audience and issuer, required expiration/issued-at/auth-time/UID checks, and bounded UID length. JWT key-source headers cannot change the trusted endpoint. No `test-token-*` bypass remains in application code.
2. **Account linking/role escalation.** An existing account could be selected by email as an alternative to UID. Authentication now queries only the verified Firebase `sub`; automatically provisioned accounts receive `volunteer`. Token and body roles never grant privileges.
3. **Missing authorization.** Previously volunteers could access patient/financial/photo data and change administrative settings. Middleware now preserves the policy already expressed in `database.rules.json`: clinical, room/stay, attendance, payment, photo, counter, and settings reads require admin/staff; settings writes require admin; ERP reads permit authenticated users, ERP writes admin/staff; existing admin-only patient deletion remains enforced. No user-role management endpoint was found.
4. **Sensitive error leakage and incorrect failure classification.** Authentication returned raw database exception text as a 401. Role lookup/provisioning failures now return a generic 503; invalid tokens return a generic 401. `/ready` no longer includes raw connection errors.
5. **Production configuration was incomplete.** Backend did not identify its Firebase project; compose passed irrelevant signing secrets. `FIREBASE_PROJECT_ID` is now mandatory in production and passed through Compose. `.env.example` matches the public project ID in `.firebaserc`. Production configuration rejects the built-in/example database passwords. Pool minimum must not exceed maximum; configured connection URL must use a PostgreSQL protocol.
6. **Container startup omitted upgrades.** Runtime now executes `node dist/db/migrate.js up` before starting the server on every start, including an existing named database volume. Compiled JavaScript is used because the production image omits `tsx`. This entrypoint change is source/configuration-verified here; actual container execution is reported by the main database audit.

## Automated evidence

Commands executed from `backend/` unless stated otherwise:

| Command | Observed result | Evidence type |
|---|---|---|
| `npm test -- --reporter=dot tests/config.test.ts tests/health.test.ts` before edits | 9 tests passed | Existing mocked tests; no PostgreSQL integration |
| `npm test -- --reporter=dot tests/auth.test.ts` before auth fix | 27 failures / 29 tests; one failure was a test-fixture `undefined exp` signing issue subsequently corrected, the other mismatches exposed missing validation/authorization or unsafe errors | Regression reproduction |
| `npm test -- --reporter=dot tests/auth.test.ts tests/firebase_verifier.test.ts tests/domain_routes.test.ts tests/config.test.ts tests/health.test.ts` after scoped changes | 61 tests passed across 5 files (32 auth, 10 key verifier, 5 existing domain, 9 config, 5 health) | Real JWT signatures + Fastify injection; database and key HTTP responses mocked |
| `npm run build` after initial auth implementation | TypeScript build completed successfully | Compiler |
| Later `npm run build` during parallel root validation edits | Failed at `src/validation.ts:49` because a route URL was possibly undefined; reported to root for its owned file | Compiler; requires final root rerun |
| Root: `docker compose --env-file .env.example config --quiet` | Exit 0 | Compose syntax/configuration only; no runtime proof |
| Root: `git diff --check` | Exit 0, existing LF/CRLF warnings | Diff whitespace only |
| `npm audit --omit=dev --json` | Exit 1; 4 high findings: fastify, find-my-way, node-pg-migrate, glob | Package advisory audit; findings are remaining cutover risks |

Synthetic RSA keys are created in process memory by `tests/helpers/auth.ts`; no private test key or real identity is committed. Existing domain tests now use signed tokens and a mocked Google certificate response rather than the removed bypass.

The key-verifier tests exercise signature validation, algorithm confusion, fixed key endpoint despite malicious `jku`/`x5u`, unknown `kid`, key rotation before cache expiry, `Cache-Control: max-age` expiry, concurrent request fetch coalescing, key-source failures, and recovery. Authentication tests exercise wrong project/issuer, expired/missing expiration, future times, empty/oversized/conflicting UID, non-string audience, fabricated tokens, server-authoritative roles, email account linking, administrative privileges, safe database failures, and missing project configuration.

## Deployment and data safety inspection

- PostgreSQL 16 is declared and has no published host port. Its named volume is `ngo-pgdata`; no volume deletion was performed by this audit worker.
- Container runs as the unprivileged `node` user. Its current health probe checks process liveness; `/ready` checks database connectivity.
- Compose now requires explicit database password and Firebase project configuration and fixes `NODE_ENV=production`. Template passwords intentionally cannot start the production application until replaced.
- `.gitignore` additionally excludes environment variants, database dump/backup extensions, and temporary audit/test directories. No secret files were read or printed by this worker.
- SQL reviewed in middleware and route lookups is parameterized. Pagination SQL interpolates parsed integers; root's request validation is responsible for numeric range validation and must be retained.
- Public API port still needs the documented HTTPS reverse proxy. HTTPS termination/firewall behavior was not exercised.

## Remaining risks / limitations

1. Package advisory audit reports four high-severity production dependency findings. Installed Fastify 4 requires a major upgrade for current fixes (npm recommends Fastify 5.12.7); migration tooling's glob issue also needs remediation. No broad dependency upgrade was performed in this scoped auth change. Advisory GHSA-p68q-wchp-6fh7 concerns malformed URLs reaching encapsulated not-found handlers; this repository has no custom not-found handler, but the dependency remains affected. The root audit decides whether to upgrade and rerun all suites.
2. No live Firebase ID token was used; trusted Google fetches were mocked with synthetic public keys for deterministic tests. Certificate retrieval over the deployed network and actual client project alignment still need staging verification.
3. Token revocation/disabled-account checks are not implemented. Signature/expiry verification follows Firebase's documented basic ID-token verification; revocation requires additional authoritative Firebase state. No service-account secret was introduced.
4. Existing accounts must be imported under their actual Firebase UID. Email-only linking is intentionally removed; mismatched UIDs need a reviewed migration mapping, not automatic privilege transfer.
5. The production database user is also used for migrations and therefore has DDL capability. Separate least-privilege runtime/migration users are not configured.
6. This worker did not run container restart/persistence tests or real PostgreSQL assertions. Those results belong to the independent database/workflow audit, not the mocked security suite.

Primary verification specification consulted: [Firebase ID token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens), specifically RS256, trusted `kid`, issuer/audience, temporal claims, UID, and key-cache rules.

## Independent follow-up review of workflow changes

Read-only review of `rooms.ts`, `stays.ts`, `payments.ts`, `patients.ts`, `validation.ts`, `db/occupancy.ts`, and migrations 002/003 found and reported additional defects to the owning engineer:

- Nested room bed updates bypassed the dedicated bed endpoint's lifecycle guard. Root subsequently added prior-bed checks and restricted pointer/status changes.
- Renaming a patient retained the old derived search key. Root subsequently recomputed it when the caller changes the name without supplying a key.
- Stay update accepted `longStayDailyRate` without persisting it. Reported for correction/regression coverage.
- Patient direct updates could change active assignment fields independently of stays/beds. Reported for an active-stay guard.
- Patient absolute financial totals can overwrite a newer payment when a stale snapshot is saved. Reported as a financial consistency risk requiring a targeted policy/expected-state check or an explicit cutover blocker.

The last three statuses must be taken from the root engineer's final changes and regression results; this review does not claim those fixes were executed by the security worker.

Final scoped compiler rerun after the root validation fix: `npm run build` exited 0. Deployment documentation was updated to remove obsolete JWT signing secrets and the production `tsx` migration command; startup upgrades and the compiled migration command are now documented.

## Real PostgreSQL authentication boundary regression and migration 005

A final independent check confirmed the token verifier supports Firebase's 128-character UID limit while the SQL schema limited `users.id` and six creator/updater columns to 64. Real signed synthetic UIDs of lengths 65 and 128 therefore failed authentication with 503, and authenticated writes could not preserve their audit identity.

New files:

- `backend/migrations/005_firebase_uid_width.sql` widens `users.id`, `patients.created_by`, `stays.created_by`, `inventory_items.created_by`, `inventory_items.updated_by`, `purchases.created_by`, and `expense_entries.created_by` to `VARCHAR(128)`. Down migration deliberately retains width to avoid rejecting/truncating valid identities and historical creator data.
- `backend/tests/auth_database.integration.test.ts` exercises real auth and PostgreSQL together, with Google's certificate response mocked and actual RSA signatures verified.

Safety guards execute before any migrations/writes: `NODE_ENV=test`, `RUN_AUTH_PG_INTEGRATION=1`, connection target exactly `127.0.0.1:55439/ngo_audit_auth`, database-side database/port identity, and PostgreSQL major version 16. The parent created this dedicated disposable database. Reruns remove only this suite's exact synthetic records. No production database or broad truncation is used.

Executed command from `backend/`, with the dedicated test database connection environment configured:

`npm test -- --reporter=dot tests/auth_database.integration.test.ts`

- Before migration 005: **3 tests failed**. API provisioning returned 503 for a valid 65-character UID; a creator write returned 503; `information_schema` confirmed `users.id` was 64 characters.
- After migration 005 against the already initialized four-migration database: **3 tests passed**. Database assertions verify exact 65/128-character identities, volunteer default role, full 128-character patient/stay/inventory creator/updater values, all seven widths, and rejection of a 129-character UID with 401.
- The migration runner executed only `005_firebase_uid_width` during the successful upgrade. Database pools/application were closed before the parent's planned cluster restart.

This is real PostgreSQL API integration evidence, distinct from the earlier 61 mocked security/configuration/domain tests. Live Firebase certificate retrieval remains untested.
