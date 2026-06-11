# API Error Format

All API errors use the same envelope:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "details": {
      "amount_cents": ["must be greater than 0"]
    },
    "request_id": "2c8d1e1f-48b5-4db2-9409-88b271c7d7bb",
    "correlation_id": "client-correlation-001"
  }
}
```

Standard codes:

- `authentication_failed`: missing, invalid, or suspended API key.
- `authorization_failed`: authenticated API credential is not allowed to perform the operation.
- `idempotency_key_required`: mutating request omitted the required `Idempotency-Key` header.
- `not_found`: missing resource or cross-tenant access attempt.
- `validation_failed`: malformed input, failed model validation, or unsupported state transition.
- `insufficient_funds`: wallet projection cannot cover a debit.
- `idempotency_conflict`: key reused with a different method, full path including query string, or request body.
- `rate_limited`: request exceeded IP or API-key throttle.

Every error includes `request_id` and `correlation_id` so operators can trace the request through logs, metrics, audit records, and outbox events.
