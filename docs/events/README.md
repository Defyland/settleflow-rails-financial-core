# SettleFlow Financial Event Contracts

SettleFlow events describe committed financial state changes after ledger-backed commands succeed. They are integration, audit, and projection signals.

The double-entry ledger remains the financial source of truth. Events must never be treated as the authoritative accounting record. If an event payload disagrees with the ledger, the ledger wins and the event must be corrected or replayed.

These contracts define the canonical external event taxonomy. Internal outbox rows may use Rails/domain event names such as `pix.payment.approved`; an external publisher can map those internal names to the public event contracts below.

## Principles

- Every public financial event is versioned.
- Version `1` contracts are immutable except for backward-compatible additive changes.
- Breaking changes require a new schema file and event version.
- Consumers must be idempotent and deduplicate by `event_id`.
- Consumers must not infer account balances from event ordering alone.
- Every event must be traceable to a request, correlation ID, ledger entry, payment, wallet, payout, refund, or settlement entity when applicable.
- Events are emitted only after the database transaction that owns the financial command commits.

## Envelope

Every public financial event must include:

- `event_id`
- `event_type`
- `schema_version`
- `occurred_at`
- `producer`
- `organization_id`
- `wallet_id` or another financial entity key when applicable
- `correlation_id`
- `payload`

## Catalog

| Event | Version | Trigger | Financial meaning | Required traceability |
| --- | ---: | --- | --- | --- |
| `ledger_entry_created` | 1 | A balanced journal entry is posted | Accounting fact was persisted | `journal_entry_id`, ledger line IDs, organization |
| `balance_projection_updated` | 1 | A wallet read model changes after ledger movement | Derived balance changed | wallet, projection, source journal entry |
| `pix_payment_approved` | 1 | Pix payment passes risk and funds checks | Wallet liability was debited and Pix clearing was credited | Pix payment, wallet, approval journal entry |
| `settlement_executed` | 1 | Clearing or provider settlement is posted | Clearing and platform cash were reconciled for a payment batch or payment | settlement reference, journal entry |
| `split_posted` | 1 | A source wallet is split across destinations | Source wallet liability was debited and destination liabilities were credited | split payment, source wallet, destination wallets, journal entry |
| `payout_scheduled` | 1 | Payout is accepted for D+N settlement | Wallet liability was debited and payout clearing was credited | payout reference, wallet, schedule journal entry |
| `payout_settled` | 1 | Payout settlement completes | External payout movement is financially settled | payout reference, wallet, journal entry |
| `refund_settled` | 1 | Refund/reversal settlement completes | Customer-facing money return was financially settled | refund/reversal reference, wallet, journal entry |
| `med_case_opened` | 1 | Fake MED dispute is opened | Dispute evidence was captured without ledger mutation | MED case, Pix payment, wallet |
| `med_case_resolved` | 1 | Fake MED dispute is rejected or refunded | Dispute reached terminal state; accepted cases reference a refund | MED case, refund when present |

## Event Semantics

### `ledger_entry_created.v1`

Emitted when a `JournalEntry` with balanced `LedgerLine` rows has been committed. Consumers can use it for accounting exports, reporting pipelines, or downstream reconciliation, but they must not mutate the source ledger.

### `balance_projection_updated.v1`

Emitted when a wallet projection changes after a committed financial movement. This is a read-model signal. If a consumer needs authoritative history, it must query or ingest ledger entries rather than relying on projection deltas alone.

### `pix_payment_approved.v1`

Emitted after a Pix payment is approved and the wallet liability has been debited. It does not mean provider settlement has completed. Consumers should expect a later settlement or reversal event.

### `settlement_executed.v1`

Emitted when settlement is posted against clearing and platform cash accounts. It represents financial settlement execution, not merely scheduling.

### `split_posted.v1`

Emitted when a split posts one debit from the source wallet liability and one or more credits to destination wallet liabilities. Consumers must reconcile the total against the journal entry.

### `payout_scheduled.v1`

Emitted when a payout is scheduled for D+N settlement. It is a committed wallet debit and clearing liability, not provider cash movement.

### `payout_settled.v1`

Emitted when a payout movement reaches settled state. It must reference the settlement journal entry that debits payout clearing and credits platform cash.

### `refund_settled.v1`

Emitted when a refund or reversal reaches settled state. It must reference the original financial movement and the compensating journal entry.

### `med_case_opened.v1` and `med_case_resolved.v1`

Emitted for fake MED case state changes. Opening/rejection do not imply ledger movement; accepted cases must also produce a `refund_settled` event.

## Compatibility policy

- New optional fields may be added to `payload` without changing `schema_version`.
- Existing field meanings must not change within the same version.
- Required fields must not be removed within the same version.
- Consumers must ignore unknown optional fields.
- Replays preserve the original financial command identity and append audit evidence.
- Ledger-related events must include enough identifiers to trace back to immutable journal entries.
- Balance projection events must identify the source ledger movement or reconciliation command that caused the update.

## Ordering and Idempotency

- Ordering is guaranteed only within the database transaction that created the outbox rows.
- Cross-wallet or cross-organization ordering must not be assumed by consumers.
- Consumers must store processed `event_id` values.
- Consumers should also use business identifiers in `payload` for defensive idempotency, such as `journal_entry_id`, `pix_payment_id`, `payout_id`, or `refund_id`.

## Operational Expectations

- Failed publications remain in the outbox and are retried.
- Dead-lettered events require operator review before replay.
- Event contract drift must be handled as an incident because downstream financial consumers may be affected.
- Public event schemas should be validated in CI before release.

See [docs/runbooks/financial-event-contract-drift.md](../runbooks/financial-event-contract-drift.md) for incident handling.

The local `bin/ci` gate and GitHub Actions validate that every `*.v1.json` schema parses, that the `event_type` constant matches the filename, and that each contract defines required payload traceability fields.

## Versioned schemas

- [ledger_entry_created.v1.json](ledger_entry_created.v1.json)
- [balance_projection_updated.v1.json](balance_projection_updated.v1.json)
- [pix_payment_approved.v1.json](pix_payment_approved.v1.json)
- [settlement_executed.v1.json](settlement_executed.v1.json)
- [split_posted.v1.json](split_posted.v1.json)
- [payout_scheduled.v1.json](payout_scheduled.v1.json)
- [payout_settled.v1.json](payout_settled.v1.json)
- [refund_settled.v1.json](refund_settled.v1.json)
- [med_case_opened.v1.json](med_case_opened.v1.json)
- [med_case_resolved.v1.json](med_case_resolved.v1.json)
