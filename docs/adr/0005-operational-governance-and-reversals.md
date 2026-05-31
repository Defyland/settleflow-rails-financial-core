# ADR 0005: Operational Governance and Pix Reversals

## Status

Accepted.

## Context

An operations console that can move money needs more than authentication. Human actions require capability boundaries, audit evidence, and compensating financial workflows. The first Hotwire slice exposed settlement, rejection, outbox retry, and ledger inspection, but it did not yet distinguish read-only users from operators or admins, and it did not provide a settled Pix reversal path.

## Decision

SettleFlow will use application-level operator roles:

- `viewer`: read-only access to operational evidence.
- `operator`: can reject pending-review Pix payments and retry unpublished outbox events.
- `admin`: can perform operator actions plus settle and reverse Pix payments.

Settled Pix reversals are modeled as compensating journal entries instead of mutating historical ledger lines. A reversal debits platform cash and credits the customer wallet liability account, restoring the wallet projection while preserving the original approval and settlement entries.

Outbox publication failures retain retry state on the outbox row: attempts, error class, last error, last attempted time, next attempted time, and dead-letter time. Operators can reset unpublished events, but dead-letter rows remain incident evidence.

## Consequences

- The UI demonstrates segregation of duties without adding an external authorization gem.
- Audit logs now capture denied capabilities as well as successful operator actions.
- Reversals are explicit financial events and can be reconciled independently.
- The roles are coarse by design. SSO, MFA, and finer-grained policy objects remain future work.
