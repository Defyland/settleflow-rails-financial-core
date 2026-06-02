# Database Security

## PostgreSQL

- Use separate credentials for app, migration, and read-only analytics/export roles.
- App role should not own tables in production.
- Migration role owns DDL and is used only during deploy.
- Enforce TLS for remote database connections.
- Store credentials in deployment secrets, not repo files.
- Restrict direct SQL access to audited operator workflows.

## Financial controls

- Ledger rows are append-only through Active Record and PostgreSQL triggers.
- Journal entries require idempotency keys and domain references. Known financial journal event types must match their owning aggregate, deterministic idempotency key, expected debit/credit accounts, amount, and currency in PostgreSQL.
- Idempotency replay records are guarded in PostgreSQL: command identity is immutable, request hashes must be SHA-256 hex, succeeded responses need an HTTP status, and succeeded evidence cannot be mutated or deleted directly.
- Funding, transfer, split, Pix, payout, refund, and MED final statuses require matching PostgreSQL evidence through deferrable state triggers. Once ledger or outbox evidence exists, PostgreSQL prevents direct command identity/value mutation and deletion; only documented state transitions with new evidence are allowed.
- Balance projections cannot go negative and must match their wallet organization/currency in PostgreSQL.
- Balance snapshots are append-only projection-vs-ledger evidence; PostgreSQL enforces their wallet organization/currency and difference calculation.
- Reconciliation runs and rows are immutable after outbox evidence; PostgreSQL enforces provider-vs-ledger discrepancy math and row status evidence.
- Outbox event envelopes are immutable in PostgreSQL after insert; events must start pending/unpublished, published delivery evidence is terminal, and financial events must match a real aggregate row, organization, event type, and key payload identifiers.
- Processed-event rows must match a published outbox event by organization, public event ID, event type, and payload hash before they can drive ClickHouse ingestion state.
- Audit logs are append-only and hash-chained.
- Audit hash-chain anchors are append-only and can be exported to an external evidence sink.
- Maker-checker approvals protect operator settlement and reversal actions. PostgreSQL enforces dual-control, requires checker/timestamp evidence for terminal decisions, and blocks terminal approval mutation or deletion.

Audit anchors improve tamper evidence but do not replace regulated WORM storage. Production deployments should publish `audit:anchor_hash_chain` output to immutable storage outside the application database.

Check external anchor export readiness with:

```bash
bin/rails audit:worm_readiness_check
STRICT=true bin/rails audit:worm_readiness_check
```

The task writes `benchmarks/database/audit_worm_readiness.json` and checks HTTPS external webhook configuration, signing secret presence, and whether the latest anchor covers the current audit tail. It does not certify the destination as regulated WORM; that requires provider controls outside this repository.

## ClickHouse

- ClickHouse credentials are analytics-only.
- ClickHouse must not be used to answer authoritative balance, settlement, refund, or reconciliation decisions.
- Ingestion is deduplicated through PostgreSQL `processed_events`.

## Redis

Redis is operational only. Loss or tampering of Redis data must not change financial facts.

## Access review

Review quarterly:

- PostgreSQL users and grants.
- Migration role usage.
- ClickHouse users and table grants.
- Backup restore permissions.
- Operator accounts with financial action capabilities.
