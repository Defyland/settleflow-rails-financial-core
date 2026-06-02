# Reconciliation at Scale Runbook

1. Run provider/date reconciliation and inspect metadata totals.
2. If `projection_difference_cents` is non-zero, capture balance snapshots and run projection rebuild dry-run.
3. Use ClickHouse for large analytical event scans, not for authoritative balances.
4. Use PostgreSQL ledger queries for final accounting evidence.
5. Run `database:explain_queries` before adding indexes.
6. If query plans degrade, compare benchmark explain files and index hit ratios.
7. For repeated large discrepancies, partition ledger/audit/reconciliation tables according to the partitioning plan.

Commands:

```bash
bin/rails database:capture_balance_snapshots
bin/rails database:rebuild_balance_projections
bin/rails database:explain_queries[organization-slug]
```
