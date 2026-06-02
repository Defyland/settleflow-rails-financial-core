# ADR 0001: Double-Entry Ledger as Source of Truth

## Status

Accepted.

## Context

Wallet systems need auditability, reversibility, and provable balance movement. A mutable `wallet.balance` column is fast to query but weak for incident review, reconciliation, and accounting controls.

## Decision

SettleFlow records financial movement as balanced `JournalEntry` records with immutable `LedgerLine` rows. Wallet balances are projections derived from liability ledger lines. Each journal entry must balance debits and credits per currency before it is persisted, and known financial journal event types must match the owning command aggregate and expected account movements in PostgreSQL.

## Consequences

- Every money movement has an accounting explanation.
- Balance reads are fast through projections while the ledger remains authoritative.
- Reversals can be modeled as new entries instead of destructive edits.
- Writes are more complex because services must choose accounts and enforce transaction boundaries.
