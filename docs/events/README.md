# SettleFlow Financial Event Contracts

SettleFlow publishes the transactional outbox envelope produced by `Outbox::Publisher.envelope_for`.

The double-entry ledger remains the financial source of truth. Events are integration, audit, projection, and analytics signals. If an event payload disagrees with the ledger, the ledger wins and the event must be corrected or replayed from persisted state.

## Canonical Envelope

The public versioned contract is [outbox_event.v1.json](outbox_event.v1.json). It matches the JSON envelope actually delivered by the log and HTTP publishers:

- `id`: outbox public UUID and downstream idempotency key.
- `event_type`: internal financial event name, for example `pix.payment.approved`.
- `aggregate_type`: Rails aggregate class name.
- `aggregate_id`: database aggregate ID.
- `organization_id`: public organization UUID.
- `payload`: event-specific business payload.
- `correlation_id`: optional request correlation ID.
- `idempotency_key`: optional command idempotency key.
- `created_at`: outbox creation timestamp.

## Event Types

| Event type | Aggregate | Producer |
| --- | --- | --- |
| `wallet.funded` | `Funding` | `Fundings::Create` |
| `wallet.transfer.posted` | `Transfer` | `Transfers::Create` |
| `split.posted` | `SplitPayment` | `SplitPayments::Create` |
| `pix.payment.approved` | `PixPayment` | `PixPayments::Create` |
| `pix.payment.pending_review` | `PixPayment` | `PixPayments::Create` |
| `pix.payment.rejected` | `PixPayment` | `PixPayments::Create`, `PixPayments::Reject` |
| `pix.payment.settled` | `PixPayment` | `PixPayments::Settle` |
| `pix.payment.reversed` | `PixPayment` | `PixPayments::Reverse` |
| `payout.scheduled` | `Payout` | `Payouts::Create` |
| `payout.settled` | `Payout` | `Payouts::Settle` |
| `refund.settled` | `Refund` | `Refunds::Create` |
| `med.case.opened` | `MedCase` | `MedCases::Open` |
| `med.case.rejected` | `MedCase` | `MedCases::Reject` |
| `med.case.refunded` | `MedCase` | `MedCases::Accept` |
| `reconciliation.matched` | `ReconciliationRun` | `Reconciliation::Run` |
| `reconciliation.discrepant` | `ReconciliationRun` | `Reconciliation::Run` |

## Compatibility Policy

- Version `1` describes the envelope shape and emitted event taxonomy.
- New optional envelope fields may be added only with tests that prove publishers still emit valid envelopes.
- New `event_type` values require updating `outbox_event.v1.json`, this README, and contract tests.
- Consumers must ignore unknown payload fields.
- Consumers must deduplicate by `id`.
- Consumers must not infer account balances from event ordering alone.

## Operational Expectations

- Events are created in the same database transaction as the financial command.
- Publication happens after commit through `OutboxPublishJob`.
- `OutboxSweepJob` re-enqueues due pending and stale publishing events.
- Failed publications remain in the outbox and are retried with backoff.
- Dead-lettered events require operator review before replay.
- Event contract drift must be handled as an incident because downstream financial consumers may be affected.

See [docs/runbooks/financial-event-contract-drift.md](../runbooks/financial-event-contract-drift.md) for incident handling.
