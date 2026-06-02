# Reconciliation Data Model

Reconciliation compares provider cash statements with PostgreSQL ledger state and projection drift.

## Tables

- `reconciliation_runs`: provider/date result, provider balance, platform cash balance, discrepancy, status, metadata.
- `balance_snapshots`: wallet projection state compared with ledger-derived available balance.
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
