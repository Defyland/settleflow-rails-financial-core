# Reconciliation at Scale Runbook

1. Run provider/date reconciliation with provider statement entries when available.
2. Inspect `reconciliation_rows` by status: `discrepant`, `missing_in_ledger`, and `missing_in_provider`.
3. If `projection_difference_cents` is non-zero, capture balance snapshots and run projection rebuild dry-run.
4. Use ClickHouse for large analytical event scans, not for authoritative balances.
5. Use PostgreSQL ledger queries for final accounting evidence.
6. Run `database:explain_queries` before adding indexes.
7. If query plans degrade, compare benchmark explain files and index hit ratios.
8. For repeated large discrepancies, partition ledger/audit/reconciliation tables according to the partitioning plan.

Commands:

```bash
bin/rails database:capture_balance_snapshots
bin/rails database:rebuild_balance_projections
bin/rails database:explain_queries[organization-slug]
```
