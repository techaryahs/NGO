# Deployment and reconciliation (not executed)

No production server or database was accessed by this task.

1. Review the patch and staging evidence. Take the normal verified database backup and retain the current backend and desktop release for rollback.
2. Build the backend release using the repository's normal deployment method (`npm ci`, `npm run build` in `backend/`). Use the VPS's existing secret/configuration management; do not copy local test environment files.
3. Inspect `npm run migrate:prod:status`. This change introduces no migration. Existing migration 009 must be applied if pending because the payment API now accepts the schema's existing 128-character receipt IDs. Apply only reviewed pending forward migrations through the established release procedure (`npm run migrate:prod:up`); never reset, downgrade, or recreate the database.
4. Restart the existing backend service/container through the VPS's established deployment procedure and check `/health`, `/ready`, and authenticated staging/smoke requests. No service/container name is assumed here. For containers, rebuild the backend image and retain the database volumes.
5. Build/release the Flutter desktop application with the established production configuration and API URL (`flutter build windows --release`). Distribute the complete release bundle through the existing installer process. The installer was not modified or rebuilt by this task. Roll out the backend before the new client; old backends do not enforce the new optional `collectOutstanding` flag.
6. Check a controlled authorized admission for distinct attendee row/arrival bounds, a manual attendance save, and confirmed receipt/history/balance refresh. Creating test payments in production requires the operator's separate approved workflow; these development tests did not create real payments.

## Existing-data review

The accompanying `reconciliation-review.sql` contains SELECT queries only and was not run against production. Inspect candidates for missing active-stay snapshot identities and repeated references. Name-only legacy snapshots need human identity review; duplicate references can represent legitimate split receipts.

An operator must establish the actual attendant arrival date from admission records. The old PUT deleted/reinserted patient attendants, so `created_at` alone is not reliable arrival evidence. For live admissions, make any approved roster association correction in a dedicated audited transaction using patient locking, version checks, a recorded reason/operator, before/after snapshots, and the established billing service. Validate changed projections and preserve the receipt ledger. The ordinary Edit Details retry retains an association once established; it is not a historical reconciliation tool.

For a missing additional receipt, reconcile with bank/cash records and reference information first. An attempted action is not proof of received money. Record a new receipt only when money received is verified and use a stable unique reference. Do not automatically rewrite prior payments, merge split receipts, issue refunds, or reprice finalized invoices. Handle finalized corrections through the existing authorized adjustment workflow separately.
