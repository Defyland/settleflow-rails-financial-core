# SettleFlow Engineering Baseline

This repository follows the initiative-wide standards below.

## Mandatory outcomes

- product-grade `README.md` with product and engineering sections
- `openapi.yaml` once the HTTP surface exists
- `docs/adr/`, `docs/architecture/`, `docs/events/`, `docs/benchmarks/`, `docs/api/`, `docs/diagrams/`, and `docs/runbooks/`
- atomic Conventional Commit history
- GitHub Actions for lint, tests, security, build, coverage, and OpenAPI validation
- observability with structured logs, metrics, traces, request IDs, and readiness endpoints
- documented k6 performance baselines

## SettleFlow-specific emphasis

- double-entry ledger as the financial system of record
- balance projections derived from ledger, receivables, blocks, and settlements
- idempotent financial operations and replay-safe event consumption
- Pix lifecycle support with DICT lookup, rate limiting, antifraud scoring, and settlement outcomes
- settlement, payout, refund, MED, and reconciliation flows with explicit accounting reversals
- large report exports and analytics boundaries that remain compatible with future ClickHouse usage

## Current implementation boundary

The repository now includes the Rails 8 application, financial ledger engine, API surface, transactional outbox, settlement workers, reconciliation flow, observability endpoints, and an authenticated Hotwire operations console. Remaining roadmap items are product extensions, not baseline gaps.
