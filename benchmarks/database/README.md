# Database Benchmarks

This folder records database engineering benchmark inputs and outputs.

## Large dataset seed

```bash
bin/rails database:seed_large[1,1000,100000]
```

Arguments:

- organizations
- wallets per organization
- transfer entries per organization

The seed uses domain services so ledger, projections, idempotency, and outbox behavior stay realistic.

## Critical query plans

```bash
bin/rails database:explain_queries[database-benchmark-slug]
```

Output:

```text
benchmarks/database/explain/*.json
```

Track:

- execution time
- shared hit/read buffers
- row estimate accuracy
- sequential scans on high-volume tables
- sort/hash memory pressure

## Acceptance threshold

Before calling a dataset benchmark healthy:

- wallet statement query uses wallet/ledger indexes
- outbox publishable query uses status/date indexes
- reconciliation account aggregation stays bounded by tenant/currency
- audit chain tail reads by chain sequence index
- projection rebuild dry-run matches ledger balances
