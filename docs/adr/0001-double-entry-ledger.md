# ADR 0001: Double-Entry Ledger as Source of Truth

## Status

Accepted.

## Context

Wallet systems need auditability, reversibility, and provable balance movement. A mutable `wallet.balance` column is fast to query but weak for incident review, reconciliation, and accounting controls.

## Decision

SettleFlow records financial movement as balanced `JournalEntry` records with immutable `LedgerLine` rows. Wallet balances are projections derived from liability ledger lines. Each journal entry must balance debits and credits per currency before it is persisted.

Journal event types are a closed PostgreSQL taxonomy. Supported financial event types must match the owning command aggregate and expected account movements in PostgreSQL; unsupported event types are rejected instead of being treated as generic manual adjustments.

## Consequences

- Every money movement has an accounting explanation.
- Balance reads are fast through projections while the ledger remains authoritative.
- Reversals can be modeled as new entries instead of destructive edits.
- Writes are more complex because services must choose accounts and enforce transaction boundaries.
