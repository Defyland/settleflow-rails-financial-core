# SettleFlow

Financial core platform built in Ruby on Rails to showcase digital accounts, Pix transfers, double-entry ledger, settlement, receivables, fraud screening, reconciliation, and financial reporting inside one cohesive fintech backend.

## Status

Phase 0 bootstrap only. This repository currently establishes naming, scope, documentation structure, and engineering expectations. It does not yet contain a Rails application scaffold, ledger engine, Pix pipeline, settlement workers, or reporting implementation.

## Product intent

SettleFlow is planned as a fintech core for digital accounts that need to model how money actually moves: customer accounts and wallets, ledger-backed balances, internal transfers, Pix initiation, DICT resolution, risk scoring, receivables, D+N settlement, payouts, refunds, MED-like disputes, reconciliation, and financial reports.

## Planned stack

- Ruby on Rails API
- PostgreSQL
- Redis
- Solid Queue or Sidekiq
- Redpanda or RabbitMQ
- ClickHouse
- OpenAPI
- OpenTelemetry
- Prometheus and Grafana
- Docker Compose
- RSpec
- k6
- MinIO as an optional storage layer for reports and reconciliation artifacts

## Engineering focus

This project is meant to demonstrate:

- double-entry ledger as the source of truth instead of mutable balance fields
- derived balance projections for available, pending, blocked, and future funds
- event-driven Pix flows with DICT resolution, antifraud checks, and idempotent processing
- settlement, payout, refund, MED, and reconciliation workflows with accounting reversals
- large financial exports and analytics-friendly reporting boundaries
- senior-grade financial controls around auditability, deduplication, and failure recovery

## Bootstrap contents

- repository initialized and synchronized with GitHub
- mandatory documentation folders created, including `docs/events/`
- baseline engineering spec captured in `docs/engineering-baseline.md`

## Next phase

The first implementation slice should prioritize customers, accounts, wallets, double-entry ledger, balance projections, internal transfers, statements, and idempotent financial event handling before expanding into Pix, antifraud, settlement, and reconciliation.
