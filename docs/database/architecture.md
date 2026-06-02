# Database Architecture

SettleFlow is an OLTP-first financial core. PostgreSQL is the only source of truth for money movement, balances, idempotency, outbox state, processed events, reconciliation runs, operator approvals, and audit evidence.

## Boundaries

- PostgreSQL stores financial facts: `journal_entries`, `ledger_lines`, `balance_projections`, `balance_snapshots`, `idempotency_keys`, `outbox_events`, `processed_events`, and domain command tables.
- ClickHouse is analytics-only. It receives published outbox events and stores denormalized financial event rows for reporting, dashboards, retention-friendly exports, and large scans.
- Redis is not a source of truth. If enabled, Redis is limited to cache, rate-limit counters, and temporary non-financial locks.

## OLTP model

- `journal_entries` and `ledger_lines` are append-only double-entry records.
- `balance_projections` are derived read models and can be rebuilt from wallet liability ledger accounts.
- `balance_snapshots` capture projection-vs-ledger comparisons for daily explainability.
- `idempotency_keys` preserve write command identity and replay behavior.
- `outbox_events` preserve integration delivery evidence.
- `processed_events` records downstream processors such as ClickHouse sync and prevents duplicate analytics ingestion.

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
