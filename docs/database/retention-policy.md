# Retention Policy

Financial evidence should be retained according to regulatory and business requirements. This repo documents the policy boundary; production values depend on jurisdiction and contract.

## Recommended classes

- Ledger entries and ledger lines: retain indefinitely or until legal destruction is explicitly permitted.
- Audit logs: retain long term with hash-chain boundary evidence for archived partitions.
- Idempotency keys: retain at least the maximum replay/dispute window for financial writes.
- Outbox events and processed events: retain through consumer replay and reconciliation windows.
- Balance snapshots, reconciliation runs, and reconciliation rows: retain for operational trend analysis and incident review.
- ClickHouse analytics: retain according to reporting needs; it can be rebuilt from PostgreSQL outbox events while those are retained.

## Deletion rule

Do not delete authoritative PostgreSQL financial rows to reduce storage pressure. Archive partitions or use cold storage with restore procedures.
