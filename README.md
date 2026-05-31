# SettleFlow

SettleFlow is a Rails 8 hybrid financial-core monolith for fintech products that need tenant-aware digital accounts, double-entry ledgering, Pix-like payment lifecycle simulation, settlement, reconciliation, auditability, and an operator backoffice in one focused codebase.

## 1. What is this product?

SettleFlow models how money moves inside a digital account platform. It exposes versioned HTTP APIs for integrations and an authenticated Rails/Hotwire operations console for humans reviewing wallets, pending Pix payments, ledger entries, reconciliation exceptions, outbox events, and audit evidence.

## 2. Problem it solves

Many fintech demos store mutable balances directly on an account row. That hides the real engineering challenges: balanced accounting, idempotent commands, tenant isolation, async event publishing, fraud decisions, settlement clearing, and operational recovery. SettleFlow makes those concerns explicit and testable.

## 3. Target users

- Fintech platform teams building digital accounts or wallet products.
- Backend engineers evaluating ledger and settlement design.
- Portfolio reviewers looking for senior-level backend evidence beyond CRUD.

## 4. Main features

- Organization-scoped API credentials with HMAC digests, prefixes, scopes, revocation, expiry, and last-used tracking.
- Idempotent write endpoints using `Idempotency-Key`, atomic response persistence, stale-lock recovery, and conflict detection.
- Customers and BRL wallets.
- Double-entry journal entries and immutable ledger lines.
- Balance projections derived from wallet ledger accounts.
- Funding, internal transfer, Pix approval/review/rejection, Pix settlement, Pix reversal, and reconciliation flows.
- Authenticated `/ops` backoffice for dashboard KPIs, paginated wallet statements, Pix manual review, ledger drill-downs, reconciliation, outbox retry, and audit inspection.
- Role-based operator capabilities for read-only, operator, and admin workflows.
- Transactional outbox with pluggable log/HTTP publishers, delivery metadata, payload hashes, retry backoff, next-attempt visibility, and dead-letter evidence.
- Audit logs, request IDs, correlation IDs, Prometheus metrics, readiness checks, and OpenTelemetry wiring.
- Minitest coverage across models, services, requests, authorization, failure scenarios, jobs, ledger invariants, Rails auth, and the Hotwire operator surface.

## 5. Architecture overview

The API layer authenticates a tenant, validates idempotency, and delegates financial commands to service objects. The browser layer uses Rails auth sessions for operators and calls the same domain services for controlled actions. Services run inside database transactions, post balanced journal entries through `Ledger::JournalPoster`, update projections, and emit outbox events. Jobs publish outbox events and settle approved Pix payments asynchronously.

See [docs/architecture/overview.md](docs/architecture/overview.md).
For the senior/tech-lead evaluation rationale, see [docs/architecture/senior-tech-lead-validation.md](docs/architecture/senior-tech-lead-validation.md).

## 6. Tech stack

- Ruby `3.4.2`
- Rails `8.1`
- PostgreSQL with `pgcrypto`
- ERB, Turbo, Stimulus, Importmap, and Propshaft
- Rails auth generator, bcrypt, Action Mailer, and Active Storage
- ActiveJob, Solid Queue, Solid Cache, and Solid Cable
- Minitest, fixtures, Capybara system tests, and SimpleCov
- Prometheus client, Rack::Attack, OpenTelemetry SDK
- Brakeman, bundler-audit, RuboCop
- k6 for load tests
- Docker, Thruster, Kamal, and GitHub Actions

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

SettleFlow uses a transactional outbox table and ActiveJob jobs. Financial services emit events in the same database transaction as ledger mutations, then enqueue `OutboxPublishJob`. The job publishes through a configurable adapter, stores delivery metadata, and only marks events published after the adapter acknowledges. Approved Pix payments enqueue `PixSettlementJob`. See [docs/events/messaging.md](docs/events/messaging.md) and the versioned contract policy in [docs/events/README.md](docs/events/README.md).

## 10. Database design

The schema uses foreign keys, unique constraints per tenant, check constraints for ledger directions and account types, positive amount checks, UUID public IDs, and optimistic locking on wallets/projections. Money is stored as integer cents. Ledger entries are the source of truth; projections are derived read models.

## 11. Testing strategy

Run:

```bash
bin/rails test
bin/rails test:system
```

Coverage includes unit/model tests, service integration tests, API request tests, authorization, idempotency, failure scenarios, outbox jobs, Pix lifecycle, reconciliation, database-backed ledger invariants, Rails auth, and the operator system flow.

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

- API credentials are stored as HMAC-SHA256 digests with lookup prefixes, optional expiry, revocation, scopes, and last-used timestamps. Legacy organization API key digests remain supported for seed/demo compatibility.
- All v1 endpoints require `X-Api-Key`.
- Human operators authenticate through Rails sessions backed by `bcrypt` password hashes.
- Tenant isolation is enforced by scoping every query through `current_organization`.
- Rack::Attack throttles by IP and API key.
- Idempotency prevents duplicate financial commands.
- Inputs are validated at service/model/database layers.
- Secrets are supplied through environment variables.
- Operator roles gate Pix settlement/reversal and outbox retries.
- Audit logs record API actions, operator decisions, denied capabilities, status, request ID, correlation ID, IP, and filtered parameters.

See [docs/architecture/security.md](docs/architecture/security.md) and [docs/security/threat-model.md](docs/security/threat-model.md).

## 15. Trade-offs and decisions

ADRs are in [docs/adr](docs/adr):

- double-entry ledger as source of truth
- transactional outbox with Solid Queue
- API key authentication plus idempotent command handling
- ledger plus outbox before full Event Sourcing
- hybrid Rails monolith with Hotwire Ops backoffice
- operational governance, outbox retry state, and Pix reversal controls

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

Default development operator:

```text
email: ops@settleflow.local
password: password123
```

Optional PostgreSQL via Docker:

```bash
docker compose up db
```

## 17. How to run tests

```bash
bin/rails db:test:prepare
COVERAGE=1 bin/rails test
bin/rails test:system
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
ruby -rjson -e 'Dir["docs/events/*.v1.json"].sort.each { |path| JSON.parse(File.read(path)); puts "#{path} parsed" }'
```

`bin/ci` runs the full local gate, including tests, security checks, OpenAPI parsing, and financial event contract validation.

## 18. Failure scenarios

Covered and documented scenarios include:

- duplicate idempotency keys with different payloads
- insufficient funds
- unbalanced journal entries
- cross-tenant resource access
- Pix risk rejection and manual review
- outbox retry/dead-letter behavior
- operator authorization denial
- reconciliation discrepancies
- unauthenticated operator access
- manual Pix rejection and reversal with operator audit trail

Operational steps are in [docs/runbooks/incident-response.md](docs/runbooks/incident-response.md).

## 19. Roadmap

- Add OIDC/SAML SSO, MFA, and finer-grained permission groups for operators.
- Add real DICT provider adapters and webhook ingestion.
- Add full MED/dispute case management around the reversal ledger primitive.
- Add ClickHouse export path for reporting.
- Add multi-currency ledger support.
- Add RabbitMQ/Redpanda adapters when measured throughput or integration fanout exceeds the built-in log/HTTP outbox publishers.
- Add selected browser tests for pagination and multi-role review queues as the Ops surface grows.
