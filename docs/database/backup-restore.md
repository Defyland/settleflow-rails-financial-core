# Backup and Restore

PostgreSQL backups protect the financial source of truth. ClickHouse can be rebuilt from PostgreSQL outbox events when retention permits.

## PostgreSQL

- Use continuous WAL archiving with point-in-time recovery.
- Take regular logical or physical backups.
- Test restore into an isolated environment.
- Verify ledger balance sums, projection rebuilds, reconciliation counts, and audit hash-chain integrity after restore.

## ClickHouse

- Back up analytics tables for faster reporting recovery.
- If ClickHouse is lost, restore schema with `clickhouse:create_schema` and backfill with `clickhouse:backfill`.

## Restore validation

Run:

```bash
bin/rails runner 'abort("audit hash chain broken") unless AuditLog.hash_chain_intact?'
bin/rails database:rebuild_balance_projections
bin/rails database:explain_queries
```
