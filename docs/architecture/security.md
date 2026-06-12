# Security Notes

For the money-specific threat model, see [docs/security/threat-model.md](../security/threat-model.md).

## Threat model

Primary risks:

- Cross-tenant data access.
- Duplicate financial commands from client retries.
- Overdrafts during concurrent debits.
- API key leakage.
- Operator session compromise.
- Event loss after a committed financial transaction.
- Missing operational evidence during incidents.

## Controls

- Every v1 query is scoped by authenticated organization.
- API credentials are issued once, stored as HMAC-SHA256 digests, looked up by non-secret prefixes, and can be scoped, expired, or revoked. Legacy organization API key digests are disabled by default and only available through development/test compatibility configuration.
- Operators authenticate through Rails sessions and `bcrypt` password hashes.
- Browser forms use Rails CSRF protection.
- Operator roles gate human workflows: every ops-console read surface and every mutation (settle, reject, reverse, MED approval, outbox retry) requires the `admin` role. `viewer` and `operator` are global staff roles that currently hold no ops-console capability; they exist for a future organization-scoped model. See [decisions](../decisions.md).
- Mutating endpoints support idempotency records keyed by organization. Financial command effects and idempotency response persistence share the same database transaction, and stale processing locks can be retried.
- Wallet projections use optimistic locking and row locks for debit checks.
- Database constraints enforce unique tenant references and positive amounts.
- `Rack::Attack` throttles by IP and HMAC-digested API-key discriminators so raw credentials are not reused as cache keys.
- Audit logs capture request status and filtered params.
- Structured logs include request and correlation IDs.
- Outbox events prevent event loss after ledger commits, use claim leases to avoid concurrent duplicate publishing, and record delivery metadata after adapter acknowledgement.

## Authorization matrix

Every row in the ops-console column below requires the `admin` role; non-admin `viewer`/`operator` users are denied both reads and mutations.

| Resource | Tenant/API access | Ops console access (admin role) |
| --- | --- | --- |
| Customers | Same organization only | Read through related wallets and ledger evidence |
| Wallets | Same organization only | Read statements and projections |
| Fundings | Same organization only | Read through ledger entries |
| Transfers | Source and destination wallets must belong to same organization | Read through ledger entries |
| Pix payments | Same organization only | Read, settle approved payments, reject pending-review payments, reverse settled payments |
| Ledger entries | Same organization only | Read immutable entries and lines |
| Reconciliation runs | Same organization only | Read run status and metadata |
| Outbox events | Not exposed through v1 public API | Read and retry unpublished events |
| Audit logs | Not exposed through v1 public API | Read API and operator actions |

## Secrets

Use environment variables for production secrets:

- `DATABASE_URL`
- `SETTLEFLOW_RAILS_FINANCIAL_CORE_DATABASE_PASSWORD`
- `RAILS_MASTER_KEY`
- `SETTLEFLOW_OPERATOR_EMAIL`
- `SETTLEFLOW_OPERATOR_PASSWORD`
- `OTEL_EXPORTER_OTLP_ENDPOINT`
- `RATE_LIMIT_PER_MINUTE`
- `RATE_LIMIT_PER_API_KEY_PER_MINUTE`
- `OUTBOX_WEBHOOK_URL`
- `OUTBOX_WEBHOOK_SECRET`
- `OUTBOX_HTTP_OPEN_TIMEOUT`
- `OUTBOX_HTTP_READ_TIMEOUT`
