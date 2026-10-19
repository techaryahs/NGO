# Disposable backend test environment — 18 October 2026

Scope: test runtime setup, existing backend test execution, and this evidence file. No application files or existing NGO data were changed by this worker. This evidence does not establish that any desktop workflow was executed.

Gravitas policy: compact planning, dependency context, impact verification, delegated execution. Docker resource creation is isolated from the existing Compose stack; all database mutation is restricted to an explicitly disposable test target.

## Runtime isolation

- Existing `ngo-backend` on port 8080 and `ngo-postgres` were running before this work. They were not stopped, recreated, or reset by this worker.
- Created dedicated container `ngo-desktop-qa-pg16-20261018` from the existing `postgres:16-alpine` image.
- Published only `127.0.0.1:55439:55439`; PostgreSQL itself listens on 55439 so database-side integration guards check the same port.
- Database `ngo_audit_workflows`, synthetic user `ngo_audit`, test-only trust authentication. No existing database volume is attached. Docker may create an anonymous volume for the PostgreSQL image; no existing volumes were removed.
- Observed `pg_isready`: `127.0.0.1:55439 - accepting connections`.
- Observed identity: `ngo_audit_workflows|55439|160015` (PostgreSQL 16.15).

Creation command:

```powershell
docker run --detach --name ngo-desktop-qa-pg16-20261018 --publish 127.0.0.1:55439:55439 --env POSTGRES_USER=ngo_audit --env POSTGRES_DB=ngo_audit_workflows --env POSTGRES_HOST_AUTH_METHOD=trust postgres:16-alpine postgres -p 55439
```

Workflow tests were handed to the registration worker exclusively. Use `NODE_ENV=test`, `POSTGRES_HOST=127.0.0.1`, `POSTGRES_PORT=55439`, `POSTGRES_DB=ngo_audit_workflows`, `POSTGRES_USER=ngo_audit`, `DATABASE_URL=postgres://ngo_audit@127.0.0.1:55439/ngo_audit_workflows`, and `RUN_PG_INTEGRATION=1`. Explicit `DATABASE_URL` overrides any existing `.env` connection. The suite checks the exact target before migration/truncation. Do not run simultaneous suites that truncate this same database.

## Unit baseline

Initial `npm test -- --reporter=dot`, all integration opt-ins disabled, with `POSTGRES_PORT=55439`: **69 passed, 1 failed, 74 skipped**. Failure was `config.test.ts:14`, which unconditionally expects `config.POSTGRES_PORT` to equal 5432. This was an environment-sensitive test configuration failure; no application behavior was changed to satisfy it.

Reran with the configuration value `POSTGRES_PORT=5432` expected by that test while keeping `DATABASE_URL` explicitly pointed to the inert disposable target `127.0.0.1:55439/ngo_audit_inert_unit`. That database was not created; no live application database is reachable through the test URL. All integration opt-ins remained disabled.

Observed result: **6 files passed, 6 files skipped; 70 tests passed, 84 skipped; 8.09 seconds**. Full output: `backend-unit-baseline.log` in this directory. The skipped count increased because another worker added workflow integration cases during the run; the enabled unit tests all passed.

The attempted first log redirection did not execute tests because this audit directory did not yet exist. The directory was created, then the successful baseline run above produced the log.

VERDICT: PASS

## Final regression run after backend registration changes

Registration worker released the disposable workflow database after its changes to `backend/src/routes/patients.ts` and `backend/tests/workflows.integration.test.ts`. This worker then executed the complete current workflow file independently:

```powershell
$env:NODE_ENV='test'
$env:POSTGRES_HOST='127.0.0.1'
$env:POSTGRES_PORT='55439'
$env:POSTGRES_DB='ngo_audit_workflows'
$env:POSTGRES_USER='ngo_audit'
$env:DATABASE_URL='postgres://ngo_audit@127.0.0.1:55439/ngo_audit_workflows'
$env:RUN_PG_INTEGRATION='1'
npx vitest run tests/workflows.integration.test.ts --reporter=dot
```

Observed: **32/32 passed**, 8.365 seconds test execution, 13.36 seconds total. Full output: `backend-workflows-final.log`. Coverage includes fresh/rerunnable migrations, patient validation/field preservation, rooms/beds, concurrent admission conflicts, atomic registration rollback, retry identity conflicts, same-patient registration concurrency, same-bed conflicts, multi-bed discharge isolation, attendants, attendance JSONB merge, payment idempotency/precision/rollback, safe connection replacement and saturated-pool timeout. The log's PostgreSQL `57P01` idle-client error occurs in the intentional backend-termination resilience case; the case passed.

The workflow benchmark reported in-process Fastify/PostgreSQL times (milliseconds): registration 82.38 using the prior multi-request sequence versus 39.10 using atomic registration; patient retrieval 7.46; rooms retrieval 5.54; attendance prior sequence 50.75 versus bounded retrieval 6.73; payment plus balance refresh 15.57; discharge prior sequence 61.87 versus targeted sequence 29.95. These synthetic measurements **do not include Flutter or desktop click/render latency**, and are not before/after desktop measurements.

Final unit rerun after the same changes: **70 passed, 85 skipped; 6 files passed, 6 skipped; 6.26 seconds total** (`backend-unit-final.log`). The preceding password-free trust URL attempt failed one config test because its regex requires a `user:password@` URL. That attempt is preserved as `backend-unit-trusturl-attempt.log`; the successful rerun restored the same synthetic URL format used for the passing baseline. No code was modified in response.

Final read-only database identity/count check: `ngo_audit_workflows|55439|160015`; patients 2; stays 2; occupied beds 0. These are the final synthetic benchmark records after both patients were discharged. They are not the desktop application's data.

VERDICT: PASS

## Explicit limitations

- Module suite requires `inet_server_addr()` to be loopback. A host-to-Docker bridge connection reports the container address, so that suite has not been run in this runtime.
- Persistence suite requires a native temporary cluster and `pg_ctl` control. It has not been run against Docker. Native PostgreSQL 16 binaries exist, but no native runtime was started.
- No desktop interaction was performed by this test-environment worker. Desktop interaction belongs to the parent task and remains necessary for the user's requested verification.
