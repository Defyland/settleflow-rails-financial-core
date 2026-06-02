# Incident Runbooks

## API latency spike

1. Check `GET /ready` and `GET /metrics`.
2. Inspect `settleflow_http_request_duration_seconds` by path.
3. Check PostgreSQL connections and slow queries.
4. Verify rate-limit counters and client retry behavior.
5. Scale web workers or reduce abusive traffic.

## Pending outbox events

1. Open `/ops/outbox_events?status=pending` and sort by `next_attempt_at`.
2. Start workers with `bin/jobs` or `bin/rails solid_queue:start`.
3. Inspect `attempts`, `error_class`, `last_error`, and `last_attempted_at`.
4. Retry manually only after confirming the downstream publisher is healthy.
5. Preserve `dead_lettered` events as incident evidence; do not delete rows to hide failed delivery.

## Reconciliation discrepancy

1. Find the `ReconciliationRun` by provider/date.
2. Compare `provider_balance_cents`, `ledger_balance_cents`, and `discrepancy_cents`.
3. Inspect `metadata.platform_cash_cents`, `wallet_liability_cents`, `projection_available_cents`, `projection_difference_cents`, `pix_clearing_cents`, and `payout_clearing_cents`.
4. If `projection_difference_cents` is non-zero, use `/v1/wallets/:id/balance_explanation` for affected wallets and compare statement running balances with projections.
5. Inspect journal entries for the statement date and verify funding, transfer, split, Pix, payout, refund, and MED-originated refund entries.
6. Post a correcting financial command only after root cause is documented and approved; do not edit ledger rows or projection rows directly.

## Pix reversal

1. Confirm the Pix payment is `settled`; pending or approved payments use rejection/cancellation paths, not reversal.
2. Verify provider evidence that money returned or must be restored to the customer wallet.
3. Use an admin operator in `/ops/pix_payments/:id` to reverse with a reason.
4. A second admin must approve the maker-checker request before the reversal executes; do not edit `operator_approvals` directly because terminal approvals are immutable PostgreSQL governance evidence.
5. Confirm the reversal journal entry is balanced and the wallet projection increased by the Pix amount.
6. If a `refund` already exists for the Pix payment, do not use direct reversal; continue with the refund/MED evidence path.
7. Preserve the audit log, `pix.payment.reversed` outbox event, and reconciliation evidence for the incident record.

## Payout D+N issue

1. Find the `Payout` by `public_id` or `external_id` and confirm `status`, `settlement_due_on`, and `settlement_journal_entry_id`.
2. If the payout is `scheduled`, confirm wallet available balance was already debited and `PAYOUT_CLEARING:<currency>` was credited.
3. Do not settle before `settlement_due_on` through the public API. Early settlement must be requested by one operator and approved by a second operator through maker-checker action `payout.settle_early`.
4. After early settlement, verify `payout.operator_approval_id` references an approved approval for the same payout and `bin/rails database:verify_consistency` reports `payout_early_settlement_mismatches=0`.
5. If settlement was retried, confirm there is only one `payout.settled` journal entry and one deterministic key `payout.settle:<id>`.
6. If provider cash differs after settlement, run reconciliation for the provider date and preserve the outbox event `payout.settled`.

## Refund or MED dispute

1. Confirm the source Pix payment is `settled`.
2. Sum existing settled refunds for the Pix payment and verify the requested refund does not exceed the original Pix amount.
3. Run `bin/rails database:verify_consistency` and confirm `financial_state_evidence_guards.refund_limit_mismatches=0`.
4. For MED, open a `MedCase` first; terminal resolution must be requested in `/ops` and approved by a second admin through maker-checker.
5. When a MED case is accepted, verify the case references an approved `operator_approval` with action `med_case.accept` and exactly one linked settled `refund` using deterministic key `med_case.refund:<id>`.
6. If a MED case is rejected, verify the case references an approved `operator_approval` with action `med_case.reject` and no refund or journal entry was created for that case.
7. Do not mix direct Pix reversal with settled refunds for the same Pix payment.

## Split mismatch

1. Find the `SplitPayment` and confirm `total_amount_cents` equals the sum of `split_entries.amount_cents`.
2. Confirm the journal has one debit from the source wallet liability and one credit per destination wallet liability.
3. Compare each destination wallet statement running balance with `/v1/wallets/:id/balance_explanation`.
4. If a destination is wrong, do not edit split entries or ledger lines; create an explicit compensating transfer or refund-style financial command after approval.

## Audit hash-chain failure

1. Run `bin/rails database:verify_consistency`.
2. Inspect `AuditLog.hash_mismatches`, `AuditLog.broken_chain_links`, and `AuditLog.invalid_genesis_links`.
3. Compare the latest `AuditLogAnchor` with the external `AUDIT_ANCHOR_WEBHOOK_URL` destination if configured.
4. Treat any mismatch as evidence of database-level tampering or an unsafe maintenance script.
5. Preserve a physical database backup before attempting repair.
6. Do not update or delete audit rows or anchors; database triggers intentionally block mutation.

## Duplicate command or idempotency conflict

1. Look up `idempotency_keys` by organization and key.
2. Compare method, path, and request hash.
3. If the previous response succeeded, replay it to the caller.
4. If payload differs, return `409 idempotency_conflict`.
5. For settlements and reversals, also inspect deterministic journal keys such as `pix_payment.settle:<id>`, `payout.settle:<id>`, and `med_case.refund:<id>`.
6. Never manually delete idempotency rows for posted financial commands.

## Insufficient funds reports

1. Read wallet balance projection and `/v1/wallets/:id/balance_explanation`.
2. Inspect wallet statement running balances and find the first line where available balance would go negative.
3. Verify pending Pix, scheduled payout, split, transfer, and refund commands are represented in ledger entries.
4. Confirm there is no cross-tenant wallet reference in the request.
5. Never raise the projection manually to satisfy a payout or transfer; fix the missing ledger event or reject the command.

## Ledger repair policy

1. Ledger rows are append-only; direct `UPDATE` or `DELETE` is an incident, not a repair path.
2. Financial corrections must be explicit compensating commands with a unique idempotency key, correlation ID, operator approval where applicable, and outbox evidence.
3. If a console repair is unavoidable, document the exact journal event type, debit/credit accounts, amount, currency, approval, and reconciliation evidence before execution.
4. After repair, run the full reconciliation for affected provider dates and `bin/rails database:verify_consistency`.
