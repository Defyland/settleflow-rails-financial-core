# ClickHouse Analytics

ClickHouse is used for analytical financial event scans and reporting. It is not authoritative.

## Sync path

1. Financial service writes PostgreSQL domain rows, ledger rows, projection updates, and outbox rows in one transaction.
2. `OutboxPublishJob` publishes the outbox event.
3. If `CLICKHOUSE_URL` is configured, `ClickHouseSyncJob` is enqueued.
4. `Analytics::ClickHouseSync` inserts a denormalized event row into ClickHouse with `JSONEachRow`.
5. `processed_events` records processor status and prevents duplicate ingestion.

## Schema

`clickhouse:create_schema` creates each DDL object in a separate HTTP request:

- database: `CLICKHOUSE_DATABASE`, default `settleflow`;
- event table: `CLICKHOUSE_FINANCIAL_EVENTS_TABLE`, default `financial_events`;
- daily rollup table: `CLICKHOUSE_DAILY_ROLLUP_TABLE`, default `financial_event_daily_rollups`;
- materialized view: `CLICKHOUSE_DAILY_ROLLUP_VIEW`, default `financial_event_daily_rollups_mv`.

The application validates ClickHouse identifiers before sending SQL. ClickHouse table names cannot be used as raw SQL input.

## Tasks

```bash
bin/rails clickhouse:create_schema
bin/rails clickhouse:backfill[1000]
```

## Environment

- `CLICKHOUSE_URL`
- `CLICKHOUSE_DATABASE`
- `CLICKHOUSE_FINANCIAL_EVENTS_TABLE`
- `CLICKHOUSE_DAILY_ROLLUP_TABLE`
- `CLICKHOUSE_DAILY_ROLLUP_VIEW`
- `CLICKHOUSE_USERNAME`
- `CLICKHOUSE_PASSWORD`

## Failure model

ClickHouse sync failure does not roll back PostgreSQL financial state. Failed sync rows remain in `processed_events` and can be retried with the backfill task.
