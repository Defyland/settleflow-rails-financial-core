# Messaging and Outbox Architecture

SettleFlow uses a transactional outbox and ActiveJob. Publisher delivery is adapter-based: the default adapter writes a canonical event envelope to structured logs, and `OUTBOX_WEBHOOK_URL` enables an HTTP publisher that posts the same envelope with the outbox public ID as the downstream idempotency key. This keeps the repository self-contained while preserving the seam needed for RabbitMQ, Redpanda, Pub/Sub, or webhook delivery.

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

## Publisher mapping

Current adapters:

- `Outbox::Publishers::LogPublisher`: local/default adapter for self-contained deployments and tests.
- `Outbox::Publishers::HttpPublisher`: posts JSON envelopes to `OUTBOX_WEBHOOK_URL`, requires a 2xx response, and records the response `X-Message-ID` when present.

Future RabbitMQ mapping:

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
- Publishing increments `attempts` only after the configured adapter is called.
- Successful publication stores publisher name, destination, downstream message ID, and a SHA-256 hash of the canonical envelope.
- Failed publication records `error_class`, `last_error`, `last_attempted_at`, and a `next_attempt_at` backoff timestamp.
- Events move to `dead_lettered` only after the retry budget is exhausted.
- Operators can manually reset unpublished events through `/ops/outbox_events`.
- Jobs acknowledge work only after the outbox row is updated.
