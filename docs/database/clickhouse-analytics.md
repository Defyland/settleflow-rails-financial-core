# ClickHouse Analytics

ClickHouse is used for analytical financial event scans and reporting. It is not authoritative.

## Sync path

1. Financial service writes PostgreSQL domain rows, ledger rows, projection updates, and outbox rows in one transaction.
2. `OutboxPublishJob` publishes the outbox event.
3. If `CLICKHOUSE_URL` is configured, `ClickHouseSyncJob` is enqueued.
4. `Analytics::ClickHouseSync` inserts a denormalized event row into ClickHouse with `JSONEachRow`.
5. `processed_events` records processor status, stores the outbox envelope hash, rejects hash drift, requires a matching published outbox event in PostgreSQL, and prevents duplicate ingestion.

## Schema

`clickhouse:create_schema` creates each DDL object in a separate HTTP request:

- database: `CLICKHOUSE_DATABASE`, default `settleflow`;
- event table: `CLICKHOUSE_FINANCIAL_EVENTS_TABLE`, default `financial_events`;
- daily rollup view: `CLICKHOUSE_DAILY_ROLLUP_VIEW`, default `financial_event_daily_rollups`.

The application validates ClickHouse identifiers before sending SQL. ClickHouse table names cannot be used as raw SQL input.

The event table uses `ReplacingMergeTree(synced_at)` ordered by `event_id`. Inserts also send `insert_deduplication_token=event_id`. The daily rollup is a normal ClickHouse view over `financial_events FINAL`, so analytical counts deduplicate retried inserts by event ID.

## Tasks

```bash
bin/rails clickhouse:create_schema
bin/rails clickhouse:backfill[1000]
CLICKHOUSE_URL=http://localhost:8123 bin/rails clickhouse:verify
```

## Environment

- `CLICKHOUSE_URL`
- `CLICKHOUSE_DATABASE`
- `CLICKHOUSE_FINANCIAL_EVENTS_TABLE`
- `CLICKHOUSE_DAILY_ROLLUP_VIEW`
- `CLICKHOUSE_USERNAME`
- `CLICKHOUSE_PASSWORD`
- `CLICKHOUSE_OPEN_TIMEOUT`
- `CLICKHOUSE_READ_TIMEOUT`
- `CLICKHOUSE_WRITE_TIMEOUT`

## Failure model

ClickHouse sync failure does not roll back PostgreSQL financial state. Failed sync rows remain in `processed_events` and can be retried with the backfill task.

PostgreSQL still owns processor state. ClickHouse dedupe prevents duplicated analytical counts when a retry repeats an insert for the same `event_id`, but it is not a source of truth and must not be used to repair financial balances. PostgreSQL rejects processed-event rows unless they match a published outbox event by organization, public event ID, event type, and payload hash. If the stored outbox hash differs from the current outbox envelope hash, the sync fails instead of inserting an ambiguous analytics row.
