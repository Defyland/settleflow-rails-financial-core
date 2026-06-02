# ClickHouse Analytics

ClickHouse is used for analytical financial event scans and reporting. It is not authoritative.

## Sync path

1. Financial service writes PostgreSQL domain rows, ledger rows, projection updates, and outbox rows in one transaction.
2. `OutboxPublishJob` publishes the outbox event.
3. If `CLICKHOUSE_URL` is configured, `ClickHouseSyncJob` is enqueued.
4. `Analytics::ClickHouseSync` inserts a denormalized event row into ClickHouse.
5. `processed_events` records processor status and prevents duplicate ingestion.

## Tasks

```bash
bin/rails clickhouse:create_schema
bin/rails clickhouse:backfill[1000]
```

## Environment

- `CLICKHOUSE_URL`
- `CLICKHOUSE_DATABASE`
- `CLICKHOUSE_FINANCIAL_EVENTS_TABLE`
- `CLICKHOUSE_USERNAME`
- `CLICKHOUSE_PASSWORD`

## Failure model

ClickHouse sync failure does not roll back PostgreSQL financial state. Failed sync rows remain in `processed_events` and can be retried with the backfill task.
