# Deployment Readiness

SettleFlow needs a Rails API, operator surface, PostgreSQL, Solid Queue workers, and future provider adapters for Pix, payout, refund, and reconciliation flows.

## Current posture

- Rails API and Hotwire operations console.
- PostgreSQL-backed ledger, projections, sessions, and outbox events.
- Health, readiness, metrics, structured logs, and OpenTelemetry hooks.
- CI and benchmark coverage for the financial workflow slice.

## Deferred platform work

- Kubernetes manifests are deferred until ledger, settlement, and provider adapter processes stabilize.
- Service mesh is out of scope for the MVP; idempotency, audit logs, row locks, and outbox delivery are the primary safeguards.
- Managed secrets and external audit storage should be introduced before real financial provider credentials are used.
