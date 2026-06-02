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

## Itemized Rows

`Reconciliation::Run` always creates rows for provider cash balance and projection-vs-ledger balance. When provider statement entries are supplied, it also matches each provider entry against PostgreSQL ledger entries using the journal `metadata.external_id` and the platform cash ledger account for the statement date.

Row statuses:

- `matched`: provider and ledger amounts agree.
- `discrepant`: provider and ledger both have the item but amounts differ.
- `missing_in_ledger`: provider sent an item that has no matching platform cash ledger entry.
- `missing_in_provider`: PostgreSQL has a platform cash ledger entry for the statement date that is absent from the provider statement.

The run status is `discrepant` when any reconciliation row is not matched.
