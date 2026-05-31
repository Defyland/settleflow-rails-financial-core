# Financial Event Contract Drift

Use this runbook when consumers cannot process SettleFlow financial events.

## Triage

- Confirm ledger entries still exist and balance projections can be rebuilt.
- Identify the schema under `docs/events/` and the originating outbox row.
- Verify `organization_id`, wallet or entity key, `event_id`, and `correlation_id`.
- Check whether the consumer confused projection state with ledger truth.

## Recovery

- Restore the compatible event payload.
- Replay outbox events only after confirming ledger invariants still hold.
- Do not rewrite ledger entries to satisfy a consumer contract.
- Add a new schema version for breaking changes.
