# ADR 0002: Transactional Outbox with Solid Queue

## Status

Accepted.

## Context

Financial workflows emit integration events after ledger changes. Publishing directly to a broker inside request code risks losing events when the DB commits but the broker call fails, or publishing events for transactions that later roll back.

## Decision

Services write `OutboxEvent` rows in the same transaction as ledger mutations. `OutboxPublishJob` publishes pending rows asynchronously. Solid Queue provides the local production-grade ActiveJob backend, while the outbox table preserves replay and dead-letter state.

## Consequences

- Event creation is atomic with financial state changes.
- Publishing can be retried independently.
- A future RabbitMQ or Redpanda adapter can replace the simulated publisher without changing domain services.
- Operators need runbooks for pending and dead-lettered events.
