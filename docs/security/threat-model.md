# Money Threat Model

This document focuses on threats that can create incorrect money state, hide the cause of money movement, or expose one tenant's financial data to another tenant.

## Scope

In scope:

- wallet balances and balance projections
- journal entries and ledger lines
- Pix payment state, settlement, rejection, and reversal evidence
- idempotency keys
- outbox events carrying financial changes
- reconciliation runs and discrepancy evidence
- operator actions and audit logs

Out of scope for the MVP:

- real banking rail compromise
- card network disputes
- regulatory case management
- external WORM storage
- provider-specific Pix/MED protocol rules

## Assets At Risk

- ledger entries and ledger lines
- wallet balance projections
- Pix payment state and reversal evidence
- idempotency keys and outbox events
- reconciliation runs and discrepancy evidence
- operator sessions and audit logs

## Trust Boundaries

- Tenant API clients call financial endpoints with API keys.
- Human operators use Rails sessions for settlement, reversal, rejection, and outbox actions.
- Background jobs publish events after committed ledger mutations.
- Future payment rails, payout providers, refund providers, and reconciliation sources are external systems.
- Database constraints and transactions are inside the trusted persistence boundary.

## Primary Threats

| Threat | Scenario | Impact | Current controls | Production follow-up |
| --- | --- | --- | --- | --- |
| Negative balance | Concurrent debits read the same available balance and both commit | Wallet shows spend beyond available funds | Row locks, projection checks, positive amount constraints, ledger invariants, service-level insufficient-funds checks | Add high-concurrency load tests per hot wallet, lock-order documentation, database isolation review |
| Duplicate money movement | Client retries a timed-out funding, transfer, Pix payment, payout, or refund request | Customer is debited or credited more than once | Organization-scoped idempotency keys, unique tenant references, request hash conflict detection | Add retention policy, replay dashboard, provider idempotency key mapping |
| Cross-tenant access | API key or query bug allows tenant A to read or mutate tenant B data | Financial data leak or unauthorized movement | Every v1 query scoped by authenticated organization, service-level organization ownership checks, tenant unique indexes | Add row-level security evaluation, tenant isolation fuzz tests, security review before multi-tenant launch |
| Audit immutability failure | Operator or compromised process changes audit history after a sensitive action | Incident investigation cannot prove who did what | Audit logs are written for API/operator actions with actor, subject, request, correlation, IP, user agent, and metadata | Replicate audit stream to append-only/WORM storage, add tamper-evident hashes, restrict direct DB access |
| Reconciliation mismatch | Provider statement and internal ledger disagree | Platform cash, clearing, or liability accounts cannot be trusted | Explicit reconciliation runs, discrepancy status, ledger as source of truth, runbook evidence | Automate daily reconciliation jobs, add provider file ingestion, alert on mismatches, add aging report |
| Event loss after ledger commit | Financial mutation commits but downstream consumer never receives event | Reporting, notifications, or partner systems diverge from ledger | Transactional outbox, retry backoff, dead-letter state, operator retry | Add external broker publisher, event schema validation, DLQ replay approvals, publish latency SLO |
| Unauthorized privileged operation | Non-admin operator settles or reverses a Pix payment | Incorrect or fraudulent money movement | Role-based capabilities, authorization denial audit logs, Rails session auth | Add MFA, SSO, dual-control approvals, fine-grained permission policies |
| Ledger mutation outside domain service | Developer bypasses journal poster and writes ledger rows incorrectly | Unbalanced or unexplained financial history | Ledger validations, database constraints, service tests, ADR guidance | Add database triggers or stricter write APIs if multiple writers appear |

## Threat Details

### Negative Balance

Negative balance is primarily a concurrency and validation risk. SettleFlow checks available balance before debit operations and relies on database transactions and row locks around the balance projection. The ledger also prevents nonsensical negative amount lines by requiring positive ledger amounts and explicit debit/credit direction.

Residual risk remains around hot-wallet contention and isolation-level assumptions. Before production, the project should add stress tests for concurrent Pix and transfer debits against the same wallet.

### Duplicate Money Movement

Duplicate money movement can happen when clients retry after network timeouts or when a background job is re-run. SettleFlow treats idempotency as a financial control, not a convenience feature. Write endpoints require or support command identity, and idempotency records are scoped by organization.

The main production follow-up is retention and replay policy. High-risk endpoints should retain idempotency records long enough to cover client retry windows, provider callbacks, and operational replay scenarios.

### Cross-Tenant Access

Cross-tenant access is a critical SaaS risk. SettleFlow authenticates an organization through API keys and scopes API reads/writes through that organization. Services also reject cross-organization resource use so that a controller mistake is not the only line of defense.

Future work should consider row-level security if the app grows more direct query surfaces, reporting replicas, or tenant-admin tooling.

### Audit Immutability

The MVP writes audit logs in the application database. This is useful for product and operational review, but it is not the same as immutable external audit storage.

For production money movement, audit logs should be replicated to append-only storage, protected by narrow database privileges, and optionally chained with hashes to make tampering evident.

### Reconciliation Mismatch

Reconciliation mismatch means the provider's view of money differs from the platform ledger. The ledger remains the source of truth for internal accounting, but a mismatch is an operational incident until explained.

The MVP models reconciliation runs and discrepancy state. Production should automate provider ingestion, daily checks, alerting, and mismatch aging.

## Security Invariants

- Ledger entries are append-only financial facts.
- Balance projections are derived state and can be rebuilt.
- Outbox events are integration signals, not financial truth.
- Every financial write belongs to exactly one organization.
- Every privileged operator action must leave audit evidence.
- Reversals must be compensating entries, not destructive edits.

## Residual risks

- Ledger rows are the financial source of truth; full Event Sourcing is deferred to avoid duplicating that responsibility.
- External append-only audit storage is not yet part of the MVP.
- Real Pix, payout, and refund providers are future adapter boundaries.
- SSO, MFA, and dual-control approvals are not part of the MVP.
- Provider reconciliation is modeled but not connected to real provider files or webhooks.
