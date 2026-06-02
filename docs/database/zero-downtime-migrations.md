# Zero-Downtime Migration Strategy

Financial migrations must avoid long blocking locks and must preserve replay safety.

## Expand and contract

1. Add nullable columns or new tables.
2. Deploy code that writes both old and new state when needed.
3. Backfill in bounded batches.
4. Validate with SQL checks and service-level tests.
5. Add `NOT NULL`, check constraints, or unique constraints only after validation.
6. Remove old code paths in a later release.

## PostgreSQL practices

- Prefer `CREATE INDEX CONCURRENTLY` for large live tables.
- Avoid table rewrites during peak traffic.
- Add check constraints as `NOT VALID`, validate later, then enforce.
- Keep financial repair scripts idempotent and resumable.
- Do not roll back ledger/audit migrations without a forward data repair plan.

## Required evidence

- Migration plan.
- Backfill batch size.
- Expected lock types.
- Roll-forward plan.
- Reconciliation query before and after.
- `AuditLog.hash_chain_intact?` after completion.

## Automated Check

Run the migration safety scanner before merging database changes:

```bash
bin/rails database:migration_safety_check
STRICT=true bin/rails database:migration_safety_check
```

The scanner flags high-volume tables where indexes are not concurrent, DDL transactions are not disabled for concurrent indexes, references create blocking indexes, foreign keys are added without `NOT VALID`, or check constraints are added without delayed validation.
