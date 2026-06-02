# Database Metrics

## PostgreSQL

Track:

- transaction count and rollback count
- lock waits and deadlocks
- slow queries by fingerprint
- index hit ratio
- table and index bloat
- replication lag
- WAL generation rate
- connection pool saturation
- outbox publishable backlog
- failed `processed_events`
- reconciliation discrepancy counts
- projection difference totals

## ClickHouse

Track:

- insert latency
- rejected inserts
- parts count per partition
- query latency by dashboard
- storage by partition
- lag between `outbox_events.published_at` and `processed_events.processed_at`

## Redis

Track only operational indicators:

- key count
- memory usage
- eviction count
- command latency
- rate-limit key volume

Redis metrics must never be used as financial correctness signals.

## Application probes

Use:

```bash
GET /ready
GET /metrics
```

Production `/metrics` requires bearer authorization.
