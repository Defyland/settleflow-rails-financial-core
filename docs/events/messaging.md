# Messaging and Outbox Architecture

SettleFlow currently models broker semantics through a transactional outbox and ActiveJob. This keeps the repository self-contained while documenting the future RabbitMQ/Redpanda contract.

For public versioned financial event contracts, see [docs/events/README.md](README.md). Internal outbox event names may differ from the public contract taxonomy; publishers should map internal domain events to the versioned public schema before exposing them to external consumers.

## Event types

| Event | Producer | Purpose |
| --- | --- | --- |
| `wallet.funded` | `Fundings::Create` | Wallet funding posted |
| `wallet.transfer.posted` | `Transfers::Create` | Internal transfer posted |
| `pix.payment.approved` | `PixPayments::Create` | Pix accepted and wallet debited |
| `pix.payment.pending_review` | `PixPayments::Create` | Pix held by risk controls |
| `pix.payment.rejected` | `PixPayments::Create` | Pix blocked before ledger mutation |
| `pix.payment.settled` | `PixPayments::Settle` | Pix clearing settled against platform cash |
| `pix.payment.reversed` | `PixPayments::Reverse` | Settled Pix returned through a compensating journal entry |
| `reconciliation.matched` | `Reconciliation::Run` | Provider and ledger balances match |
| `reconciliation.discrepant` | `Reconciliation::Run` | Provider and ledger balances differ |

## Broker mapping

Future RabbitMQ mapping:

- exchange: `settleflow.events`
- queue: `settleflow.events.financial`
- retry queue: `settleflow.events.retry`
- dead-letter exchange: `settleflow.events.dlx`
- dead-letter queue: `settleflow.events.dlq`
- routing key format: `<aggregate>.<event>`

## Reliability controls

- `OutboxEvent.public_id` is the message ID.
- `correlation_id` is copied from request context.
- Consumers must use message ID for idempotency.
- Publishing increments `attempts`.
- Failed publication records `error_class`, `last_error`, `last_attempted_at`, and a `next_attempt_at` backoff timestamp.
- Events move to `dead_lettered` only after the retry budget is exhausted.
- Operators can manually reset unpublished events through `/ops/outbox_events`.
- Jobs acknowledge work only after the outbox row is updated.
