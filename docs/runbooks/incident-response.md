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
3. Inspect journal entries for the statement date.
4. Verify Pix settlements and funding entries.
5. Post a correcting journal entry only after root cause is documented.

## Pix reversal

1. Confirm the Pix payment is `settled`; pending or approved payments use rejection/cancellation paths, not reversal.
2. Verify provider evidence that money returned or must be restored to the customer wallet.
3. Use an admin operator in `/ops/pix_payments/:id` to reverse with a reason.
4. Confirm the reversal journal entry is balanced and the wallet projection increased by the Pix amount.
5. Preserve the audit log, `pix.payment.reversed` outbox event, and reconciliation evidence for the incident record.

## Duplicate command or idempotency conflict

1. Look up `idempotency_keys` by organization and key.
2. Compare method, path, and request hash.
3. If the previous response succeeded, replay it to the caller.
4. If payload differs, return `409 idempotency_conflict`.
5. Never manually delete idempotency rows for posted financial commands.

## Insufficient funds reports

1. Read wallet balance projection.
2. Inspect wallet statement endpoint.
3. Verify no pending manual-review Pix commands are expected to reserve funds.
4. Confirm there is no cross-tenant wallet reference in the request.
