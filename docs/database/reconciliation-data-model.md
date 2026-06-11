# Reconciliation Data Model

Reconciliation compares provider cash statements with PostgreSQL ledger state and projection drift.

## Tables

- `reconciliation_runs`: provider/date result, provider balance, platform cash balance, discrepancy, status, metadata. PostgreSQL enforces discrepancy math, outbox evidence, row presence, and run status consistency with row evidence.
- `reconciliation_rows`: itemized evidence for cash balance, projection balance, provider statement entries, and ledger entries missing from the provider statement. The database enforces a unique `(reconciliation_run_id, row_type, external_id)` evidence key, row type/status compatibility, amount/status compatibility, run/journal organization consistency, and immutability after reconciliation outbox evidence is emitted.
- `balance_snapshots`: wallet projection state compared with ledger-derived available balance. Rows are append-only evidence; PostgreSQL enforces wallet organization/currency consistency and the projection-minus-ledger difference.
- `journal_entries` and `ledger_lines`: source accounting evidence.
- `outbox_events`: external event evidence.

## Snapshot metadata

`Reconciliation::LedgerSnapshot` captures:

- platform cash
- Pix clearing
- payout clearing
- wallet liabilities
- projection available total
- projection difference
- wallet count
- journal entry count
- ledger line count

Any provider cash discrepancy or projection-vs-ledger difference marks the run as `discrepant`.

## Consistency Boundary

Reconciliation runs are operational snapshots, not accounting-period closes. `Reconciliation::LedgerSnapshot` records `captured_at` in run metadata, and the run compares the provider balance and optional provider statement entries against the ledger state observed during that snapshot.

Because public reconciliation creation is idempotent and already executes inside the request's idempotency transaction, the service does not try to open a stricter nested database isolation level. Operators should interpret a reconciliation run as evidence for the captured instant. If ledger writes are still in flight for the provider date, create a new run after the write window closes and preserve both runs as incident evidence.

A production period-close workflow should use an explicit cutoff, reject late writes or post them into an adjustment period, and run reconciliation after that cutoff is enforced.

## Itemized Rows

`Reconciliation::Run` always creates rows for provider cash balance and projection-vs-ledger balance. When provider statement entries are supplied, it also matches each provider entry against PostgreSQL ledger entries using the journal `metadata.external_id` and the platform cash ledger account for the statement date.

Row statuses:

- `matched`: provider and ledger amounts agree.
- `discrepant`: provider and ledger both have the item but amounts differ.
- `missing_in_ledger`: provider sent an item that has no matching platform cash ledger entry.
- `missing_in_provider`: PostgreSQL has a platform cash ledger entry for the statement date that is absent from the provider statement.

The run status is `discrepant` when any reconciliation row is not matched.
