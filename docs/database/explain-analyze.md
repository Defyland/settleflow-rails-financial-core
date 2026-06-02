# EXPLAIN ANALYZE

Critical query plans are captured by:

```bash
bin/rails database:explain_queries[organization-slug]
```

If no organization is provided, the task uses the first organization or creates a small benchmark organization.

## Covered queries

- `wallet_statement`: wallet ledger line statement with journal metadata.
- `reconciliation_accounts`: ledger account aggregation used by reconciliation snapshots.
- `outbox_publishable`: queue claim candidates for outbox publication.
- `audit_chain_tail`: latest audit hash-chain rows.

## Output

Plans are written to:

```text
benchmarks/database/explain/*.json
```

Use these files to compare plan shape, row estimates, buffers, and execution time after index or schema changes.
