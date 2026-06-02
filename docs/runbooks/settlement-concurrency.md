# Settlement Concurrency Runbook

Use this when duplicate settlement, payout, refund, or MED processing is suspected.

## Checks

1. Find the aggregate row by `public_id`.
2. Verify terminal status and journal references.
3. Count deterministic journal entries:
   - `pix_payment.settle:<id>`
   - `payout.settle:<id>`
   - `med_case.refund:<id>`
4. Inspect idempotency key rows for replay conflicts.
5. Confirm outbox events are not duplicated for the same aggregate transition.

## Expected behavior

- One worker succeeds.
- Competing workers block on row lock, re-check state, then fail validation.
- Ledger count remains one for the transition.
- Projection remains non-negative.

## Recovery

If duplicate ledger rows exist, do not mutate them. Open an incident, preserve audit evidence, and post an approved compensating financial command.
