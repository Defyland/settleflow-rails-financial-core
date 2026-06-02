# Partitioning Plan

The current schema keeps ordinary tables for developer ergonomics. Production-scale deployments should partition high-volume append-only tables after data volume justifies the operational cost.

## Candidate tables

- `journal_entries`: monthly range partition on `occurred_at`.
- `ledger_lines`: monthly range partition on `created_at`, aligned with journal entries.
- `audit_logs`: monthly range partition on `created_at`, preserving global `chain_sequence`.
- `reconciliation_runs`: yearly or monthly range partition on `statement_date`.
- `reconciliation_rows`: monthly range partition on `occurred_on`.

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

## Generated Plan

Generate future partition DDL with:

```bash
bin/rails 'database:partition_plan[6]'
bin/rails database:partition_readiness_check
bin/rails database:partition_feasibility_check
STRICT=true bin/rails database:partition_readiness_check
STRICT=true bin/rails database:partition_feasibility_check
```

The task writes SQL to `benchmarks/database/partitioning/next_partitions.sql`. The generated SQL assumes the parent tables have already been converted to partitioned tables through the copy/swap migration approach above.

`database:partition_readiness_check` queries PostgreSQL catalog tables and reports whether each candidate table is currently a partitioned parent. `STRICT=true` is expected to fail until the production copy/swap conversion has actually happened; this prevents the plan from being mistaken for implemented partitioning.

`database:partition_feasibility_check` queries PostgreSQL catalog tables and writes current blockers to `benchmarks/database/partitioning/feasibility.json`. It checks:

- primary keys and unique indexes that do not include the intended partition key
- inbound foreign keys that reference the candidate table without the partition key
- nullable or missing partition key columns
- missing supporting indexes that include the partition key

Current status is intentionally blocked, not hidden:

- `journal_entries` cannot be range-partitioned by `occurred_at` while consumers reference `journal_entries(id)` and uniqueness is enforced on `id`, `public_id`, and `(organization_id, idempotency_key)` without `occurred_at`.
- `ledger_lines` needs its primary/public identifiers remodeled or scoped by `created_at` before becoming a partitioned parent.
- `audit_logs` needs a deliberate design for global `chain_sequence` and `hash_value` uniqueness before partitioning by `created_at`.
- `reconciliation_runs` already scopes provider uniqueness by `statement_date`, but its primary/public identifiers still do not include the partition key.
- `reconciliation_rows` uses `occurred_on` for provider-line scale, but its primary/public identifiers, unique run/type/external ID key, and inbound run relationship still need partition-aware key strategy before production conversion.

The next production-grade step is not a blind migration. It is a key strategy decision:

- use composite partition-aware keys and carry partition keys into referencing tables; or
- introduce stable global key tables for references while partitioned fact tables enforce local partition constraints.

Either path must be followed by copy/swap backfill, dual-write reconciliation if needed, `database:verify_consistency`, `database:partition_readiness_check`, `database:partition_feasibility_check`, and benchmark reruns.
