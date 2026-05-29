# Security Notes

## Threat model

Primary risks:

- Cross-tenant data access.
- Duplicate financial commands from client retries.
- Overdrafts during concurrent debits.
- API key leakage.
- Event loss after a committed financial transaction.
- Missing operational evidence during incidents.

## Controls

- Every v1 query is scoped by authenticated organization.
- API keys are stored as SHA-256 digests and are never returned by the API.
- Mutating endpoints support idempotency records keyed by organization.
- Wallet projections use optimistic locking and row locks for debit checks.
- Database constraints enforce unique tenant references and positive amounts.
- `Rack::Attack` throttles by IP and API key.
- Audit logs capture request status and filtered params.
- Structured logs include request and correlation IDs.
- Outbox events prevent event loss after ledger commits.

## Authorization matrix

| Resource | Tenant access |
| --- | --- |
| Customers | Same organization only |
| Wallets | Same organization only |
| Fundings | Same organization only |
| Transfers | Source and destination wallets must belong to same organization |
| Pix payments | Same organization only |
| Ledger entries | Same organization only |
| Reconciliation runs | Same organization only |
| Outbox events | Same organization only |

## Secrets

Use environment variables for production secrets:

- `DATABASE_URL`
- `SETTLEFLOW_RAILS_FINANCIAL_CORE_DATABASE_PASSWORD`
- `RAILS_MASTER_KEY`
- `OTEL_EXPORTER_OTLP_ENDPOINT`
- `RATE_LIMIT_PER_MINUTE`
- `RATE_LIMIT_PER_API_KEY_PER_MINUTE`
