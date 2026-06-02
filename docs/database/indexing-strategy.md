# Indexing Strategy

Indexes are designed around tenant-scoped financial reads, idempotent writes, queue claims, reconciliation, and operational inspection.

## Tenant and idempotency

- Every public financial entity has a unique `public_id`.
- External command IDs are unique per organization.
- Idempotency keys are unique per organization where present.
- `processed_events` uses unique `(processor, event_id)` and `(outbox_event_id, processor)` to prevent duplicate downstream processing.

## Ledger

- `journal_entries` indexes `public_id`, `(organization_id, idempotency_key)`, `(reference_type, reference_id)`, and `(organization_id, event_type)`.
- `ledger_lines` indexes `public_id`, `(organization_id, ledger_account_id)`, and `(organization_id, created_at)`.
- Wallet statement queries join wallet liability accounts to ledger lines and order by `created_at`.

## Operations

- `outbox_events` indexes `(status, created_at)` for publishable work and `(aggregate_type, aggregate_id)` for incident drill-down.
- `audit_logs` indexes `chain_sequence`, `hash_value`, `(organization_id, created_at)`, and `(subject_type, subject_id)`.
- `operator_approvals` has a partial unique index to allow only one pending approval per action and subject.

## Reconciliation

- `reconciliation_runs` has unique `(organization_id, provider, statement_date)`.
- `balance_snapshots` has unique `(organization_id, wallet_id, currency, captured_on)` and `(organization_id, captured_on)` for daily drift scans.

## Validation

Run:

```bash
bin/rails database:explain_queries
```

The task writes `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` output into `benchmarks/database/explain`.
