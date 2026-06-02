# Partitioning Plan

The current schema keeps ordinary tables for developer ergonomics. Production-scale deployments should partition high-volume append-only tables after data volume justifies the operational cost.

## Candidate tables

- `journal_entries`: monthly range partition on `occurred_at`.
- `ledger_lines`: monthly range partition on `created_at`, aligned with journal entries.
- `audit_logs`: monthly range partition on `created_at`, preserving global `chain_sequence`.
- `reconciliation_runs`: yearly or monthly range partition on `statement_date`.

## Rules

- Keep global public IDs and tenant indexes on every partition.
- Create new partitions before the first write of a period.
- Use default partitions only as a short-lived safety net.
- Move old partitions according to retention policy, never by deleting arbitrary financial rows.
- Preserve hash-chain continuity for `audit_logs`; archive partitions with chain boundary hashes.

## Migration approach

Partitioning should be introduced with a copy/swap plan:

1. Create partitioned shadow table.
2. Backfill in bounded batches.
3. Dual-write only if required and carefully reconciled.
4. Lock briefly for final rename.
5. Validate counts, sums, hash-chain boundaries, and reconciliation snapshots.
