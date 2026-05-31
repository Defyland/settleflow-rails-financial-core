# Senior and Tech Lead Validation Guide

This guide documents the points a senior Rails interviewer should validate in SettleFlow. Each section includes the expected reasoning, the counterpoint worth challenging, why the repository stops where it stops, and the production path if the product needed the next level of rigor.

## 1. Ledger as source of truth, projections as derived state

### What the candidate should explain

Financial balances must be explainable from immutable accounting facts. SettleFlow records money movement as balanced journal entries and ledger lines. Wallet balances are read projections derived from those ledger accounts, not mutable business truth stored directly on the wallet row.

This lets the system answer audit questions such as "why is this balance what it is?", rebuild projections after bugs, and prove that every financial mutation is balanced before state changes are exposed to users.

### Counterpoint to challenge

Derived projections can become stale or inconsistent if the transaction boundary is weak. A senior candidate should acknowledge that projections improve reads, but only when they are updated atomically with the journal entry or can be rebuilt deterministically.

### Why this repository does not go further

The portfolio goal is to demonstrate ledger correctness, double-entry invariants, and projection updates inside one Rails/PostgreSQL boundary. It does not implement a full event-sourced ledger, historical balance snapshots, statement closing, or regulatory-grade reconciliation packs because those would multiply scope without improving the core architectural evidence.

### How we would continue if needed

- Add projection rebuild tasks per wallet, customer, and organization.
- Store daily/monthly balance snapshots for statements and faster historical queries.
- Add ledger period closing and immutable accounting periods.
- Add reconciliation reports comparing provider statements, platform cash, clearing accounts, and wallet liabilities.
- Add operational jobs that detect projection drift and page the team.

## 2. Pix reversal as a compensating journal entry

### What the candidate should explain

A settled Pix payment should not be "undone" by mutating or deleting the original ledger entries. SettleFlow posts a new compensating journal entry that reverses the economic effect, changes the Pix status to `reversed`, stores reversal metadata, and emits `pix.payment.reversed`.

The original approval and settlement remain auditable; the reversal becomes a separate financial fact.

### Counterpoint to challenge

A real Pix reversal is not just accounting. Production systems need dispute/MED case state, provider protocols, legal deadlines, partial reversal rules, customer notifications, and manual evidence handling.

### Why this repository does not go further

The project implements the ledger primitive and operator workflow because that is the most important engineering evidence. It intentionally does not simulate the entire Brazilian Pix dispute ecosystem, which would require external provider contracts and domain rules outside the repository scope.

### How we would continue if needed

- Introduce a `DisputeCase` or `PixReversalCase` aggregate.
- Support partial reversals with remaining reversible amount checks.
- Add provider adapter interfaces and webhook ingestion.
- Require approval workflows for high-value reversals.
- Generate customer/operator notifications and evidence bundles.

## 3. Idempotency against duplicate financial commands

### What the candidate should explain

Financial APIs must tolerate client retries. SettleFlow uses `Idempotency-Key` on write endpoints so the same command can be retried without creating duplicate ledger entries, payments, transfers, or outbox events. It rejects a reused key with a different payload, persists the command response in the same database transaction as the financial mutation, and allows retry after stale processing locks.

### Counterpoint to challenge

Idempotency is only as strong as the uniqueness boundary and stored response semantics. A senior candidate should discuss conflict windows, payload hashing, retention, retries after partial failures, and whether idempotency is scoped per tenant, endpoint, and key.

### Why this repository does not go further

The repository demonstrates tenant-scoped idempotent command handling inside PostgreSQL, including atomic response storage and stale-lock recovery. It does not implement long-term retention policies, gateway-level idempotency, replay tooling, or cross-region coordination because the deployment target is a single Rails monolith.

### How we would continue if needed

- Add retention and pruning policies by endpoint risk.
- Store normalized response envelopes for deterministic replay.
- Add dashboard filters for idempotency conflicts.
- Add integration tests for network timeout and retry scenarios.
- Move idempotency enforcement to an edge/gateway layer only if multiple write services are introduced.

## 4. Outbox retry, backoff, and dead-letter behavior

### What the candidate should explain

SettleFlow writes domain state and outbox events in the same database transaction. Active Job/Solid Queue then publishes outbox events asynchronously through a configured adapter. Failed publishing attempts remain pending with a scheduled retry; exhausted events move to `dead_lettered` with error evidence. Successful delivery stores publisher, destination, message ID, and payload hash.

This avoids the classic bug where financial state commits but the event is lost.

### Counterpoint to challenge

Database-backed queues are not a universal broker. A high-throughput integration platform may require Kafka, RabbitMQ, Pub/Sub, partitioning, consumer acknowledgements, poison-message isolation, and publisher idempotency with downstream systems.

### Why this repository does not go further

Rails 8's Solid stack is a deliberate fit for a production-minded monolith. The repo demonstrates the transactional outbox pattern, adapter-based publishing, and operational recovery without requiring broker infrastructure that the product does not yet need.

### How we would continue if needed

- Add RabbitMQ/Redpanda/Pub/Sub adapters if throughput or fanout requirements outgrow the built-in log/HTTP publishers.
- Add DLQ replay screens with approval and bulk retry controls.
- Partition outbox processing by organization or event type.
- Track publish latency, retry counts, and dead-letter rates as SLOs.
- Introduce Kafka/RabbitMQ only after measured throughput or integration requirements justify it.

## 5. Monolith and Hotwire instead of microservices or React SPA

### What the candidate should explain

This product has strong transactional boundaries and operator workflows close to the domain. A Rails monolith keeps ledger mutations, idempotency, audit logging, jobs, and operator actions in one deployable system. ERB/Hotwire is enough for backoffice workflows and avoids SPA complexity.

### Counterpoint to challenge

Microservices or a React SPA may be justified when independent teams, offline-rich UX, heavy client-side interactions, or independent scaling needs exist. A senior candidate should not defend monoliths dogmatically.

### Why this repository does not go further

The goal is a focused financial core and operations console. Adding distributed services or a frontend build stack would add operational overhead without clear product value.

### How we would continue if needed

- Extract reporting/read-heavy workloads first, not transactional ledger writes.
- Add API clients or webhooks for external consumers.
- Introduce a SPA only for workflows that need rich client state.
- Keep the ledger write model centralized unless there is a compelling regulatory or scale reason to split it.

## 6. RBAC, auditability, and tenant isolation

### What the candidate should explain

SettleFlow separates API tenant access from human operator access. API requests are organization-scoped through API credentials with prefixes, HMAC digests, scopes, revocation, expiry, and last-used tracking. Browser operations use Rails sessions and operator roles. Mutating operator actions are capability-gated through a policy object and audited with actor, request, correlation, IP, user agent, subject, and metadata.

Tenant isolation is enforced by scoping API queries through the current organization and by validating cross-organization service calls.

### Counterpoint to challenge

The role model is intentionally simple. Real organizations often need SSO, MFA, just-in-time provisioning, permission groups, approval policies, break-glass users, and stronger audit retention guarantees.

### Why this repository does not go further

The repo implements enough governance to prove senior-level design without depending on an identity provider. SSO/MFA would be better validated against a real provider such as Google Workspace, Okta, Entra ID, or Auth0.

### How we would continue if needed

- Add OIDC/SAML SSO and enforce MFA for privileged roles.
- Replace the current policy object with database-backed permission groups when customer-specific governance needs appear.
- Add dual-control approval for high-risk settlement and reversal actions.
- Add audit retention and export policies.
- Add organization membership if operators should be scoped to tenants.

## 7. Remaining pre-production risks

### What the candidate should explain

The project is production-oriented, but not production-complete. A senior or tech lead should separate what is proven in code from what needs live infrastructure, vendors, compliance, and operating procedures.

### Counterpoint to challenge

Passing tests and Docker build is not the same as operating money movement in production. The next risks are mostly integration, operational, and compliance risks rather than Rails syntax risks.

### Why this repository does not go further

This is a portfolio repository, not a regulated production rollout. It avoids fake integrations that would look realistic but provide little evidence without real provider contracts, credentials, incident history, or traffic.

### How we would continue if needed

- Deploy with Kamal to a real environment and run smoke tests after deploy.
- Wire OpenTelemetry, Prometheus, logs, and alerts to real backends.
- Run k6 regularly and track latency/error budgets.
- Add backup, restore, and disaster-recovery drills.
- Add a migration playbook for zero-downtime schema changes.
- Add provider sandbox integrations and contract tests.
- Run a threat model review and compliance gap assessment.

## What was resolved in this repository

- Ledger invariants, projection updates, atomic idempotency, stale idempotency lock recovery, outbox adapter delivery/retry/dead-letter behavior, API credential scope/revocation, RBAC denial, Pix rejection, Pix reversal, reconciliation evidence, and tenant-bound service checks are covered by automated tests.
- OpenAPI, ADRs, runbooks, diagrams, benchmark notes, CI, Docker, security scans, and Rails 8 deployment defaults are present.
- The remaining gaps are documented as intentional production follow-ups rather than hidden omissions.
