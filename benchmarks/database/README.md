# Database Benchmarks

This folder records database engineering benchmark inputs and outputs.

## Large dataset seed

```bash
bin/rails database:seed_large[1,1000,100000]
bin/rails database:benchmark[1,1000,100000]
```

Arguments:

- organizations
- wallets per organization
- transfer entries per organization

The seed uses domain services so ledger, projections, idempotency, and outbox behavior stay realistic.

`database:benchmark` seeds through the same domain services, runs `database:verify_consistency` logic against the generated organizations, captures critical `EXPLAIN` plans, evaluates threshold gates, and writes JSON evidence to:

```text
benchmarks/database/results/*.json
```

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

`database:benchmark` fails the task when any hard threshold fails:

- consistency checks are green
- generated row counts meet the expected domain-service minimums
- every critical query plan is present
- wallet statement query uses a ledger index
- outbox publishable query uses the status/date index when the dataset has at least 100 outbox rows
- plans do not spill temp files
- query execution time stays under `DATABASE_BENCHMARK_MAX_QUERY_MS`, default `250`
