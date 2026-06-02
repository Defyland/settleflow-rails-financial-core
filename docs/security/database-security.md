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
- Journal entries require idempotency keys and domain references.
- Idempotency replay records are guarded in PostgreSQL: command identity is immutable, request hashes must be SHA-256 hex, succeeded responses need an HTTP status, and succeeded evidence cannot be mutated or deleted directly.
- Funding, transfer, split, Pix, payout, refund, and MED final statuses require matching PostgreSQL evidence through deferrable state triggers.
- Balance projections cannot go negative.
- Outbox event envelopes are immutable in PostgreSQL after insert; events must start pending/unpublished, and published delivery evidence is terminal.
- Processed-event rows must match a published outbox event by organization, public event ID, event type, and payload hash before they can drive ClickHouse ingestion state.
- Audit logs are append-only and hash-chained.
- Audit hash-chain anchors are append-only and can be exported to an external evidence sink.
- Maker-checker approvals protect operator settlement and reversal actions.

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
