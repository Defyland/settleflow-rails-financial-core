# Transaction Boundaries

Financial services must complete domain state, ledger entries, balance projections, and outbox rows in one PostgreSQL transaction.

Deferrable PostgreSQL state-evidence triggers validate funding, transfer, split, Pix, payout, refund, and MED rows at commit, after the service has filled journal/refund/split references. Intermediate rows inside the transaction may be incomplete; committed rows may not be.

## Required pattern

1. Validate tenant and currency.
2. Acquire row locks on the financial aggregate or wallet projection.
3. Re-check state after lock acquisition.
4. Create or update the domain command row.
5. Post a balanced journal entry with a deterministic idempotency key.
6. Update balance projection through `Ledger::JournalPoster`.
7. Emit an outbox event inside the same transaction.
8. Commit before asynchronous publication or ClickHouse sync.

## Locked flows

- Pix settlement locks `pix_payments`.
- Payout settlement locks `payouts`.
- Refund creation locks the source `pix_payments`.
- MED acceptance locks `med_cases` and then uses refund locking on the source Pix payment.
- Transfers, splits, Pix creation, and payout scheduling lock the source wallet projection before debiting.

## Non-transactional work

- Outbox publication happens after commit.
- ClickHouse sync happens after the outbox event is published.
- Redis cache/rate-limit state is never part of financial correctness.
