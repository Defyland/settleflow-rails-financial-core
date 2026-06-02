# Redis Usage

Redis is optional operational infrastructure. It is never a source of truth for money, command state, settlement, reconciliation, outbox publication, or audit evidence.

Allowed Redis use:

- Rate-limit counters.
- Short-lived cache entries.
- Temporary non-financial locks through `Operational::TemporaryLock`.
- Feature flags or operational throttles with PostgreSQL fallback.

Forbidden Redis use:

- Wallet balances.
- Ledger lines or journal entries.
- Idempotency keys.
- Payout, refund, settlement, or MED state.
- Reconciliation evidence.
- Audit hash-chain data.

If Redis data is lost, financial correctness must be unchanged.

## Temporary Locks

`Operational::TemporaryLock` is cache-backed and requires a bounded TTL. It rejects lock keys for balances, ledger, journal entries, idempotency, payout, refund, settlement, MED, reconciliation, and audit state.

Use it only for operational coordination such as cache warming or rate-limit maintenance. PostgreSQL row locks and persistent idempotency records remain responsible for financial correctness.
