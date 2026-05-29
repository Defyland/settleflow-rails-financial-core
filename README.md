# SettleFlow

SettleFlow is a Rails API financial core for fintech products that need tenant-aware digital accounts, double-entry ledgering, Pix-like payment lifecycle simulation, settlement, reconciliation, auditability, and operational evidence in one focused backend.

## 1. What is this product?

SettleFlow models how money moves inside a digital account platform. It exposes versioned HTTP APIs for onboarding customers, opening wallets, funding balances, posting internal transfers, initiating Pix payments, settling approved Pix payments, reading ledger entries, and reconciling provider balances against the ledger.

## 2. Problem it solves

Many fintech demos store mutable balances directly on an account row. That hides the real engineering challenges: balanced accounting, idempotent commands, tenant isolation, async event publishing, fraud decisions, settlement clearing, and operational recovery. SettleFlow makes those concerns explicit and testable.

## 3. Target users

- Fintech platform teams building digital accounts or wallet products.
- Backend engineers evaluating ledger and settlement design.
- Portfolio reviewers looking for senior-level backend evidence beyond CRUD.

## 4. Main features

- Organization-scoped API key authentication.
- Idempotent write endpoints using `Idempotency-Key`.
- Customers and BRL wallets.
- Double-entry journal entries and immutable ledger lines.
- Balance projections derived from wallet ledger accounts.
- Funding, internal transfer, Pix approval/review/rejection, Pix settlement, and reconciliation flows.
- Transactional outbox with ActiveJob/Solid Queue workers.
- Audit logs, request IDs, correlation IDs, Prometheus metrics, readiness checks, and OpenTelemetry wiring.
- RSpec coverage across models, services, requests, authorization, failure scenarios, jobs, and ledger invariants.

## 5. Architecture overview

The API layer authenticates a tenant, validates idempotency, and delegates financial commands to service objects. Services run inside database transactions, post balanced journal entries through `Ledger::JournalPoster`, update projections, and emit outbox events. Jobs publish outbox events and settle approved Pix payments asynchronously.

See [docs/architecture/overview.md](docs/architecture/overview.md).

## 6. Tech stack

- Ruby `3.3.6`
- Rails `8.1`
- PostgreSQL with `pgcrypto`
- ActiveJob + Solid Queue
- RSpec, FactoryBot, Shoulda Matchers, SimpleCov
- Prometheus client, Rack::Attack, OpenTelemetry SDK
- Brakeman, bundler-audit, RuboCop
- k6 for load tests
- Docker and GitHub Actions

## 7. Domain model

Core entities:

- `Organization`: tenant boundary and API key owner.
- `Customer`: legal customer profile scoped to an organization.
- `Wallet`: customer wallet with optimistic locking and a liability ledger account.
- `LedgerAccount`: asset/liability/revenue/expense/equity account with normal balance.
- `JournalEntry` and `LedgerLine`: immutable double-entry record.
- `BalanceProjection`: read-optimized available/pending/blocked wallet balance.
- `Funding`, `Transfer`, `PixPayment`, `ReconciliationRun`: financial workflows.
- `OutboxEvent`, `IdempotencyKey`, `AuditLog`: reliability and governance records.

## 8. API documentation

OpenAPI lives in [openapi.yaml](openapi.yaml). Examples and the error envelope live in [docs/api/examples.md](docs/api/examples.md) and [docs/api/error-format.md](docs/api/error-format.md).

## 9. Async or event architecture

SettleFlow uses a transactional outbox table and ActiveJob jobs. Financial services emit events in the same database transaction as ledger mutations, then enqueue `OutboxPublishJob`. Approved Pix payments enqueue `PixSettlementJob`. See [docs/events/messaging.md](docs/events/messaging.md).

## 10. Database design

The schema uses foreign keys, unique constraints per tenant, check constraints for ledger directions and account types, positive amount checks, UUID public IDs, and optimistic locking on wallets/projections. Money is stored as integer cents. Ledger entries are the source of truth; projections are derived read models.

## 11. Testing strategy

Run:

```bash
bundle exec rspec
```

Coverage includes unit/model tests, service integration tests, API request tests, authorization, idempotency, failure scenarios, outbox jobs, Pix lifecycle, reconciliation, and database-backed ledger invariants.

## 12. Performance benchmarks

k6 scenarios are in [benchmarks/k6-financial-workflow.js](benchmarks/k6-financial-workflow.js). Methodology and baseline notes are in [docs/benchmarks/methodology.md](docs/benchmarks/methodology.md) and [benchmarks/baseline.md](benchmarks/baseline.md).

## 13. Observability

- `GET /up`: boot health.
- `GET /ready`: database readiness.
- `GET /metrics`: Prometheus text format.
- Structured JSON request logs from `RequestMetrics`.
- `X-Correlation-ID` propagation and response echo.
- OpenTelemetry instrumentation activates when `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
- Grafana dashboard definition: [docs/benchmarks/grafana-dashboard.json](docs/benchmarks/grafana-dashboard.json).

## 14. Security considerations

- API keys are stored as SHA-256 digests.
- All v1 endpoints require `X-Api-Key`.
- Tenant isolation is enforced by scoping every query through `current_organization`.
- Rack::Attack throttles by IP and API key.
- Idempotency prevents duplicate financial commands.
- Inputs are validated at service/model/database layers.
- Secrets are supplied through environment variables.
- Audit logs record API actions, status, request ID, correlation ID, IP, and filtered parameters.

See [docs/architecture/security.md](docs/architecture/security.md).

## 15. Trade-offs and decisions

ADRs are in [docs/adr](docs/adr):

- double-entry ledger as source of truth
- transactional outbox with Solid Queue
- API key authentication plus idempotent command handling

## 16. How to run locally

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails server
```

Default seed creates a demo organization. Development API key:

```text
settleflow_dev_key_change_me
```

Optional PostgreSQL via Docker:

```bash
docker compose up db
```

## 17. How to run tests

```bash
bin/rails db:test:prepare
bundle exec rspec
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

## 18. Failure scenarios

Covered and documented scenarios include:

- duplicate idempotency keys with different payloads
- insufficient funds
- unbalanced journal entries
- cross-tenant resource access
- Pix risk rejection and manual review
- outbox retry/dead-letter behavior
- reconciliation discrepancies

Operational steps are in [docs/runbooks/incident-response.md](docs/runbooks/incident-response.md).

## 19. Roadmap

- Add JWT/OIDC support beside API keys.
- Add real DICT provider adapters and webhook ingestion.
- Add MED/dispute reversal workflows.
- Add ClickHouse export path for reporting.
- Add multi-currency ledger support.
- Replace simulated outbox publishing with RabbitMQ/Redpanda adapters.
