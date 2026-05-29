# Messaging and Outbox Architecture

SettleFlow currently models broker semantics through a transactional outbox and ActiveJob. This keeps the repository self-contained while documenting the future RabbitMQ/Redpanda contract.

## Event types

| Event | Producer | Purpose |
| --- | --- | --- |
| `wallet.funded` | `Fundings::Create` | Wallet funding posted |
| `wallet.transfer.posted` | `Transfers::Create` | Internal transfer posted |
| `pix.payment.approved` | `PixPayments::Create` | Pix accepted and wallet debited |
| `pix.payment.pending_review` | `PixPayments::Create` | Pix held by risk controls |
| `pix.payment.rejected` | `PixPayments::Create` | Pix blocked before ledger mutation |
| `pix.payment.settled` | `PixPayments::Settle` | Pix clearing settled against platform cash |
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
- Failed publication moves events to `dead_lettered` with `last_error`.
- Jobs acknowledge work only after the outbox row is updated.
