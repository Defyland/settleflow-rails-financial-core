# ADR 0007: PostgreSQL Partitioned Ledger Analytics Projection

## Status

Accepted.

## Context

SettleFlow already documents that direct range partitioning of `journal_entries`
and `ledger_lines` is blocked by primary keys, unique indexes, and foreign keys
that do not include the intended partition keys. Pretending those OLTP tables
are production-partitioned would weaken the repository's credibility.

At the same time, the project needs executable evidence for database-at-scale
design beyond docs: partitioned storage, idempotent projection, query-plan
coverage, and benchmark gates that prove the projection is populated.

## Decision

Keep the double-entry ledger tables unpartitioned for the current OLTP model and
add `ledger_analytics_events` as a derived PostgreSQL projection partitioned by
`occurred_on`.

The projection is populated from immutable `JournalEntry` and `LedgerLine`
records through `Analytics::LedgerAnalyticsProjector`. Each row is idempotent by
`ledger_line_id + occurred_on`, carries wallet/account/event metadata, and stores
`signed_amount_cents` using the account's normal balance.

`Analytics::LedgerAnalyticsPartitions` creates monthly range partitions on
demand. The benchmark runner now projects seeded ledger entries and verifies
that projected analytics rows cover the ledger line count. The critical query
explainer includes a wallet/day analytics rollup query so query-plan drift is
visible in the existing database tooling.

## Options considered

| Option | Outcome | Reason |
| --- | --- | --- |
| Partition `journal_entries` and `ledger_lines` now | Rejected | Existing keys and foreign keys are not partition-aware; a safe copy/swap migration requires a separate key strategy decision |
| Keep only ClickHouse analytics | Rejected for this requirement | ClickHouse remains useful, but does not prove PostgreSQL partitioning/IaC-free local database scale inside the Rails app |
| Add a normal unpartitioned rollup table | Rejected | Easier, but would not teach partition management or partition-key constraints |
| Add a derived partitioned PostgreSQL projection | Accepted | Proves partitioned data modeling without risking the financial source of truth |

## Pros

- Demonstrates real PostgreSQL range partitioning without mutating the OLTP
  ledger contract.
- Keeps financial truth in immutable double-entry tables.
- Makes projection idempotency executable through a unique partition-aware key.
- Adds benchmark and `EXPLAIN` coverage for the analytics read path.
- Gives learners a concrete contrast between OLTP ledger design and OLAP
  projection design.

## Cons

- Adds another derived table that must be retained, rebuilt, and monitored.
- On-demand partition creation is acceptable for this demo slice, but a
  production deployment should pre-create partitions through scheduled ops.
- Projection completeness is only as fresh as the projector/job that feeds it.
- The projection does not replace ClickHouse for large external analytics scans.

## Consequences

- Future partitioning of the OLTP ledger remains intentionally blocked until key
  strategy is redesigned.
- The benchmark gate now fails if ledger analytics projection rows fall behind
  ledger lines.
- Any future analytics query should read the projection or ClickHouse, not scan
  the OLTP ledger tables by default.
- A production hardening pass should add scheduled partition creation, retention
  policy, and projection lag metrics.

## Evidence

- `db/migrate/20260707130000_create_ledger_analytics_events.rb` creates the
  partitioned parent table and indexes.
- `app/services/analytics/ledger_analytics_projector.rb` projects immutable
  ledger lines idempotently.
- `test/services/ledger_analytics_projector_test.rb` proves partition creation,
  idempotency, signed wallet movement, and projection immutability.
- `lib/database/benchmark_runner.rb` populates the projection during benchmark
  setup.
- `lib/database/benchmark_thresholds.rb` verifies projection completeness.
- `lib/database/critical_query_explainer.rb` captures the analytics wallet/day
  query plan.
