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
- API keys are stored as SHA-256 digests and are never returned by the API.
- Operators authenticate through Rails sessions and `bcrypt` password hashes.
- Browser forms use Rails CSRF protection.
- Operator roles gate human workflows: viewers are read-only, operators can reject pending-review Pix and retry outbox events, and admins can settle or reverse Pix payments.
- Mutating endpoints support idempotency records keyed by organization.
- Wallet projections use optimistic locking and row locks for debit checks.
- Database constraints enforce unique tenant references and positive amounts.
- `Rack::Attack` throttles by IP and API key.
- Audit logs capture request status and filtered params.
- Structured logs include request and correlation IDs.
- Outbox events prevent event loss after ledger commits.

## Authorization matrix

| Resource | Tenant/API access | Operator access |
| --- | --- | --- |
| Customers | Same organization only | Read through related wallets and ledger evidence |
| Wallets | Same organization only | Read statements and projections |
| Fundings | Same organization only | Read through ledger entries |
| Transfers | Source and destination wallets must belong to same organization | Read through ledger entries |
| Pix payments | Same organization only | Read, settle approved payments, reject pending-review payments, reverse settled payments |
| Ledger entries | Same organization only | Read immutable entries and lines |
| Reconciliation runs | Same organization only | Read run status and metadata |
| Outbox events | Same organization only | Read and retry unpublished events |
| Audit logs | Same organization only where applicable | Read API and operator actions |

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
