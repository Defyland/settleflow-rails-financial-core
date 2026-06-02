# Database Failure Runbook

## PostgreSQL unavailable

1. Stop write traffic if `/ready` fails.
2. Confirm database host, connection pool saturation, locks, and disk.
3. Do not route financial writes to ClickHouse or Redis.
4. Preserve failed requests with correlation IDs.
5. Restore PostgreSQL from primary, replica, or backup.
6. After recovery, run projection rebuild dry-run and reconciliation for affected dates.

## Lock contention

1. Inspect blocked sessions and lock wait events.
2. Identify aggregate rows: wallet, Pix payment, payout, MED case, or outbox event.
3. Do not kill sessions blindly during financial transactions.
4. If a session must be terminated, verify idempotency replay and ledger counts afterward.

## Restore validation

```bash
bin/rails database:verify_consistency
bin/rails database:backup_restore_drill
bin/rails database:pitr_readiness_check
bin/rails database:rebuild_balance_projections
bin/rails database:explain_queries
```

`database:backup_restore_drill` is a logical restore drill. Do not claim PITR readiness from that command alone.

For PITR incidents, validate the external restore chain before reopening writes:

1. Confirm the restored base backup and WAL archive cover the target time.
2. Recover into an isolated PostgreSQL instance with the target timestamp or LSN.
3. Run `database:verify_consistency`, projection rebuild dry-run, reconciliation for affected dates, and critical query explains.
4. Compare restored WAL LSN and incident timeline before promoting the instance.
