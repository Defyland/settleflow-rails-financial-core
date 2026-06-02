# Database Architecture

SettleFlow is an OLTP-first financial core. PostgreSQL is the only source of truth for money movement, balances, idempotency, outbox state, processed events, reconciliation runs and rows, operator approvals, and audit evidence.

## Boundaries

- PostgreSQL stores financial facts: `journal_entries`, `ledger_lines`, `balance_projections`, `balance_snapshots`, `idempotency_keys`, `outbox_events`, `processed_events`, `reconciliation_runs`, `reconciliation_rows`, and domain command tables.
- ClickHouse is analytics-only. It receives published outbox events and stores denormalized financial event rows for reporting, dashboards, retention-friendly exports, and large scans.
- Redis is not a source of truth. If enabled, Redis is limited to cache, rate-limit counters, and temporary non-financial locks.

## OLTP model

- `journal_entries` and `ledger_lines` are append-only double-entry records.
- Financial command states for funding, transfer, split, Pix, payout, refund, and MED are guarded by deferrable PostgreSQL triggers so final statuses require the expected journal, refund, split-entry, or failure evidence at commit.
- `balance_projections` are derived read models and can be rebuilt from wallet liability ledger accounts. PostgreSQL prevents projection rows whose wallet, organization, or currency do not match.
- `balance_snapshots` capture projection-vs-ledger comparisons for daily explainability. PostgreSQL keeps snapshots append-only and enforces `difference_cents = available_cents - ledger_available_cents`.
- `idempotency_keys` preserve write command identity and replay behavior. PostgreSQL checks the request hash format and response state, keeps command identity immutable, prevents direct successful-record insertion, and blocks mutation/deletion of succeeded replay evidence.
- `reconciliation_runs` and `reconciliation_rows` preserve provider-vs-ledger discrepancy evidence.
- `outbox_events` preserve integration delivery evidence. PostgreSQL blocks direct published inserts, envelope mutation, deletion, and any mutation after an event is published.
- `processed_events` records downstream processors such as ClickHouse sync, validates against a published outbox event, stores the outbox payload hash, and prevents duplicate analytics ingestion.
- `audit_log_anchors` stores append-only anchor records for exported audit hash-chain tail evidence.

## OLAP model

ClickHouse table `settleflow.financial_events` receives JSONEachRow rows from published outbox events:

- `event_id`
- `event_type`
- `aggregate_type`
- `aggregate_id`
- `organization_id`
- `correlation_id`
- `idempotency_key`
- `payload`
- `payload_sha256`
- `occurred_at`
- `synced_at`

The analytics table is partitioned by event month and deduplicated by `event_id` with `ReplacingMergeTree(synced_at)`.

`clickhouse:create_schema` also creates a daily rollup view for event counts and amount sums by organization, event type, and day. The view reads `financial_events FINAL` so retried inserts with the same `event_id` do not inflate analytical counts. These objects are analytical only and must not feed authoritative balance, settlement, refund, or reconciliation decisions.

## Audit anchoring

`audit:anchor_hash_chain` records the current audit hash-chain tail in `audit_log_anchors`. Anchors are append-only, chained to the previous anchor, included in `database:verify_consistency`, and can be exported to `AUDIT_ANCHOR_WEBHOOK_URL`. `audit:worm_readiness_check` verifies that external anchor export is configured, signed, and fresh. This is tamper-evidence and export readiness; regulated WORM storage still requires an external immutable destination.
