# Database Architecture

SettleFlow is an OLTP-first financial core. PostgreSQL is the only source of truth for money movement, balances, idempotency, outbox state, processed events, reconciliation runs and rows, operator approvals, and audit evidence.

## Boundaries

- PostgreSQL stores financial facts: `journal_entries`, `ledger_lines`, `balance_projections`, `balance_snapshots`, `idempotency_keys`, `outbox_events`, `processed_events`, `reconciliation_runs`, `reconciliation_rows`, and domain command tables.
- ClickHouse is analytics-only. It receives published outbox events and stores denormalized financial event rows for reporting, dashboards, retention-friendly exports, and large scans.
- Redis is not a source of truth. If enabled, Redis is limited to cache, rate-limit counters, and temporary non-financial locks.

## OLTP model

- `journal_entries` and `ledger_lines` are append-only double-entry records. PostgreSQL enforces a closed journal event taxonomy: `wallet.funded`, `wallet.transfer.posted`, `split.posted`, `pix.payment.approved`, `pix.payment.settled`, `pix.payment.reversed`, `payout.scheduled`, `payout.settled`, and `refund.settled`. Any new money movement type requires an explicit migration before it can post ledger lines.
- For every supported journal event type, PostgreSQL also verifies that the journal reference, idempotency key, account directions, account identities, amounts, and currency match the funding, transfer, split, Pix, payout, or refund aggregate that owns the movement.
- Financial command states for funding, transfer, split, Pix, payout, refund, and MED are guarded by deferrable PostgreSQL triggers so final statuses require the expected journal, refund, split-entry, approval, or failure evidence at commit. PostgreSQL also freezes command identity/value fields and blocks deletion once ledger or outbox evidence exists, while allowing only documented lifecycle transitions such as payout settlement, Pix settlement/reversal, and MED resolution.
- MED terminal states require maker-checker approval evidence. PostgreSQL verifies that rejected cases reference an approved `med_case.reject` approval, and refunded cases reference an approved `med_case.accept` approval plus a settled refund for the same Pix payment, amount, currency, and deterministic `med_case.refund:<id>` idempotency key.
- `balance_projections` are derived read models and can be rebuilt from wallet liability ledger accounts. PostgreSQL prevents projection rows whose wallet, organization, or currency do not match.
- `balance_snapshots` capture projection-vs-ledger comparisons for daily explainability. PostgreSQL keeps snapshots append-only and enforces `difference_cents = available_cents - ledger_available_cents`.
- Funding, transfer, split, Pix, payout, refund, and MED command rows must carry a nonblank `idempotency_key` enforced by PostgreSQL, not only by service validations. Their organization-scoped unique indexes then make duplicate command identity a database-level conflict instead of an application convention.
- `idempotency_keys` preserve HTTP write replay behavior. PostgreSQL checks the request hash format and response state, keeps request identity immutable, prevents direct successful-record insertion, and blocks mutation/deletion of succeeded replay evidence.
- `reconciliation_runs` and `reconciliation_rows` preserve provider-vs-ledger discrepancy evidence. PostgreSQL enforces run discrepancy math, row amount/status compatibility, run-vs-row status consistency, outbox evidence, and immutability after evidence is emitted.
- `operator_approvals` preserve maker-checker evidence. PostgreSQL enforces dual-control, pending-vs-terminal evidence, and immutable terminal approvals.
- `outbox_events` preserve integration delivery evidence. PostgreSQL blocks direct published inserts, envelope mutation, deletion, any mutation after an event is published, and events whose aggregate type, aggregate row, organization, event type, command idempotency key, or key payload identifiers do not match a real financial fact. Terminal MED events additionally require payload evidence for `operator_approval_id`, `refund_id` when refunded, terminal status, and `resolved_at`.
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
