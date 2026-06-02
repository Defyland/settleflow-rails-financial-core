# ClickHouse Sync Failure Runbook

ClickHouse failure is an analytics incident, not a financial correctness incident.

1. Confirm PostgreSQL `outbox_events` remain published and immutable.
2. Inspect `processed_events` with processor `clickhouse_financial_events`.
3. Check ClickHouse availability and insert errors.
4. Recreate schema if needed:

```bash
bin/rails clickhouse:create_schema
```

5. Backfill published outbox events:

```bash
bin/rails clickhouse:backfill[10000]
```

6. Compare processed event count with published outbox count.
7. Do not rewrite PostgreSQL financial rows to repair analytics.
