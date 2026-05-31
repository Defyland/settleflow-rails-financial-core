# ADR 0002: Transactional Outbox with Solid Queue

## Status

Accepted.

## Context

Financial workflows emit integration events after ledger changes. Publishing directly to a broker inside request code risks losing events when the DB commits but the broker call fails, or publishing events for transactions that later roll back.

## Decision

Services write `OutboxEvent` rows in the same transaction as ledger mutations. `OutboxPublishJob` claims publishable rows with a short lease, publishes them asynchronously through a log or HTTP adapter, and marks them published only after adapter acknowledgement. Solid Queue provides the local production-grade ActiveJob backend, while the outbox table preserves replay and dead-letter state.

## Consequences

- Event creation is atomic with financial state changes.
- Publishing can be retried independently.
- Concurrent workers skip rows already claimed by another worker; stale publishing leases can be reclaimed.
- A future RabbitMQ or Redpanda adapter can replace the built-in log/HTTP publishers without changing domain services.
- Operators need runbooks for pending, publishing, and dead-lettered events.
