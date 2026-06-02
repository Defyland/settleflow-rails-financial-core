# Backup and Restore

PostgreSQL backups protect the financial source of truth. ClickHouse can be rebuilt from PostgreSQL outbox events when retention permits.

## PostgreSQL

- Use continuous WAL archiving with point-in-time recovery.
- Take regular logical or physical backups.
- Test logical restore into an isolated environment with `bin/rails database:backup_restore_drill`.
- Check WAL/PITR readiness with `bin/rails database:pitr_readiness_check`.
- Verify ledger balance sums, projection rebuilds, reconciliation counts, and audit hash-chain integrity after restore.

`database:backup_restore_drill` proves that a logical `pg_dump`/`pg_restore` can be restored and validated. It is not a physical PITR drill.

`database:pitr_readiness_check` reads PostgreSQL settings and writes `benchmarks/database/pitr_readiness.json`. It checks that:

- `wal_level` supports PITR (`replica` or `logical`)
- `archive_mode` is `on` or `always`
- `archive_command` or `archive_library` is configured and not a fake no-op command
- `max_wal_senders` is positive
- the current WAL LSN is observable

A full production PITR drill still requires external backup infrastructure: base backups, WAL archive storage, restore host, recovery target, `restore_command`, and a timed recovery validation against financial consistency checks.

## ClickHouse

- Back up analytics tables for faster reporting recovery.
- If ClickHouse is lost, restore schema with `clickhouse:create_schema` and backfill with `clickhouse:backfill`.

## Restore validation

Run:

```bash
bin/rails database:verify_consistency
bin/rails database:backup_restore_drill
bin/rails database:pitr_readiness_check
bin/rails database:rebuild_balance_projections
bin/rails database:explain_queries
```
