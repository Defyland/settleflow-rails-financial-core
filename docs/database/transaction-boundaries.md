# Transaction Boundaries

Financial services must complete domain state, ledger entries, balance projections, and outbox rows in one PostgreSQL transaction.

API idempotency records are part of the same transaction boundary. PostgreSQL guards the request hash, response state, immutable request identity, and succeeded replay evidence. The financial command tables also require nonblank `idempotency_key` values at the database layer, so direct inserts cannot create funding, transfer, split, Pix, payout, refund, or MED rows outside replay identity controls.

Deferrable PostgreSQL state-evidence triggers validate funding, transfer, split, Pix, payout, refund, and MED rows at commit, after the service has filled journal/refund/split/approval references. Intermediate rows inside the transaction may be incomplete; committed rows may not be.

Balance projection amount updates are allowed only inside the ledger posting or projection rebuild transaction after the application sets the local PostgreSQL `settleflow.balance_projection_write_context`. Direct SQL updates to `available_cents`, `pending_cents`, or `blocked_cents` are rejected even when the resulting values are non-negative.

Mutation guards run before updates/deletes on those command tables. Identity and value fields are immutable after insert, rows with ledger/outbox evidence cannot be deleted, and state changes after evidence are limited to the documented lifecycle transitions that add settlement, reversal, refund, or rejection evidence.

Financial journal-evidence triggers are also deferrable. They allow the service to create the aggregate, journal entry, ledger lines, and aggregate journal pointer in one transaction, then reject the commit unless the supported journal event type matches the aggregate reference, deterministic idempotency key, expected accounts, debit/credit directions, amount, and currency.

`journal_entries.event_type` is a closed PostgreSQL check constraint, not a free-form label. Adding a new ledger movement requires a migration that extends the taxonomy and aggregate-evidence function in the same deployment path.

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
- Payout settlement locks `payouts`; early settlement before `settlement_due_on` must pass ops maker-checker and store the approved `operator_approval` on the payout.
- Refund creation locks the source `pix_payments`; PostgreSQL also locks the source Pix row on direct refund writes and rejects cumulative settled refunds above the Pix amount.
- MED acceptance/rejection requires ops maker-checker. The checker execution locks `med_cases`; acceptance then uses refund locking on the source Pix payment and stores the approved operator approval on the MED case.
- Transfers, splits, Pix creation, and payout scheduling lock the source wallet projection before debiting.

## Non-transactional work

- Outbox publication happens after commit.
- ClickHouse sync happens after the outbox event is published.
- Redis cache/rate-limit state is never part of financial correctness.
