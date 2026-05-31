# ADR 0006: Double-Entry Ledger Before Full Event Sourcing

## Status

Accepted.

## Context

SettleFlow handles financial state. The system needs a durable way to explain why a wallet balance changed, how settlement affected platform cash, and how refunds or reversals compensate previous movement.

There are two related but different concepts:

- A double-entry ledger records accounting facts. It proves that every financial movement balances debit and credit entries per currency.
- Event Sourcing records domain events as the primary persistence model and rebuilds aggregate state by replaying those events.

Both models use immutable records, but they are not interchangeable. If SettleFlow adopted pure Event Sourcing while also keeping a double-entry ledger, the MVP would have two conceptual sources of truth for money: event streams and ledger entries. That would make replay, projection rebuilds, corrections, and audit explanations harder to reason about.

## Decision

The double-entry ledger is the financial source of truth.

SettleFlow uses:

- immutable `JournalEntry` and `LedgerLine` records for money movement
- `BalanceProjection` records as derived read models
- `AuditLog` records for governance and operator evidence
- transactional outbox events for integration and downstream projection signals

Pure Event Sourcing is outside the MVP. Outbox events are not the financial source of truth; they describe committed ledger-backed changes for consumers.

## Alternatives Considered

### Mutable wallet balances only

This would be simpler to implement, but it would make audit, reversal, reconciliation, and incident review weak. A single mutable balance does not explain the accounting path that produced it.

### Pure Event Sourcing

This would provide replayable domain history, but it would require event store tooling, event version migrations, aggregate replay rules, snapshots, and projection rebuild procedures. It would also duplicate the conceptual responsibility already handled by the ledger.

### Double-entry ledger plus transactional outbox

This is the selected option. It keeps financial correctness grounded in accounting invariants while still giving integrations a reliable event stream after commits.

## Consequences

- Balance correctness remains grounded in accounting invariants.
- Integration events can evolve independently from ledger records.
- Projection rebuilding is based on ledger entries, not on replaying all domain events.
- Outbox replay is an integration recovery mechanism, not a financial correction mechanism.
- Event Store, aggregate snapshotting, and event migration tooling are deferred until a concrete product need appears.
- Engineers must avoid treating public events as accounting truth.

## Revisit Criteria

This decision should be revisited if SettleFlow needs:

- event-sourced aggregates outside the financial ledger
- independent product teams owning separate bounded contexts
- long-lived external event replay guarantees for consumers
- a regulatory requirement for an append-only event store distinct from the ledger
- multi-region write coordination that changes the persistence model
