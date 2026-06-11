# Public Release Remediation Spec

Status: active
Started: 2026-06-11
Owner: Codex

## Goal

Make SettleFlow safe and coherent enough for a public GitHub release by resolving the audit findings that undermine senior-level review: domain-state enforcement, API authorization, audit/PII handling, transactional outbox reliability, public contract drift, operational consistency, documentation truthfulness, and maintainability debt.

## Non-Goals

- Do not redesign the product into a different architecture.
- Do not replace the double-entry ledger.
- Do not introduce new external infrastructure requirements.
- Do not weaken existing database invariants to make tests pass.
- Do not perform broad formatting sweeps or unrelated refactors.

## Verification Baseline

Required before marking the remediation complete:

- `bin/rails test`
- `bin/rails test:system`
- `bin/rubocop`
- `bin/brakeman`
- `bin/bundler-audit`
- `bin/rails zeitwerk:check`
- `bin/rails database:verify_consistency`
- `bin/rails database:migration_safety_check`
- OpenAPI YAML parse/lint
- Event schema parse/validation checks
- `git status --short` clean after commits

## Atomic Commit Policy

Each commit must contain one coherent remediation unit:

1. Spec or journal only.
2. Domain-state policy and tests.
3. API credential scope/legacy-key hardening and tests.
4. Audit sanitization/deduplication and tests.
5. Outbox relay/rescue reliability and tests.
6. Public event contract alignment and tests.
7. API/OpenAPI contract fixes and tests.
8. Consistency/snapshot/rebuild fixes and tests.
9. PII/idempotency/retention fixes and tests.
10. Lower-priority maintainability/docs cleanup.

## Requirements

### R1: Enforce wallet and customer lifecycle state

Problem: `Wallet` and `Customer` expose `active`, `blocked`, and `closed`, but money services and wallet creation ignore those states.

Acceptance:

- Funding rejects inactive wallets.
- Transfer rejects inactive source or destination wallets.
- Pix creation rejects inactive wallets before creating Pix state.
- Payout, split payment, refund/MED flows reject inactive wallets where applicable.
- Wallet creation rejects inactive customers.
- Tests prove blocked/closed state cannot move money or open wallets.

### R2: Remove or contain legacy organization API key bypass

Problem: legacy `Organization.authenticate_api_key` bypasses `ApiCredential` scopes, revocation, and expiry.

Acceptance:

- Public API authorization no longer allows unscoped legacy keys outside an explicit development/test compatibility path.
- Tests prove revoked or read-only `ApiCredential` behavior still works.
- Tests prove legacy keys cannot bypass write-scope enforcement in production-like configuration.
- Seeds issue scoped `ApiCredential` keys or are development/test-only.

### R3: Make audit logging accurate and sanitized

Problem: validation failures can produce both an error audit and a request audit with misleading status, and audit metadata stores raw request parameters with PII.

Acceptance:

- One API request produces one audit record unless an explicit secondary security event is intentional.
- Error responses are audited with the final error status and error code.
- Audit parameter metadata is allowlisted or redacted; `document_number`, `pix_key`, `receiver_name`, `destination_reference`, free-form `metadata`, and secrets are not stored raw.
- Audit logging failure does not mask the original API error response.
- Tests cover success, validation error, and PII redaction.

### R4: Fix transactional outbox reliability

Problem: `OutboxEvent.publishable` and stale-publishing recovery are not driven by production recurring work. `OutboxPublishJob` can mark an already published event as failed if a post-publish side effect fails.

Acceptance:

- A recurring sweep job claims and enqueues publishable outbox events.
- The sweep job handles pending-due and stale-publishing events.
- `OutboxPublishJob` failure handling covers only publish failure, not downstream analytics enqueue failure.
- Analytics sync enqueue failure cannot revert a published outbox event.
- Tests prove sweep behavior and no duplicate publish regression.

### R5: Align public event contracts with actual envelopes

Problem: `docs/events/*.json` describe public snake_case event names and fields that differ from the actual outbox envelope and payloads.

Acceptance:

- Public schemas match the actual emitted envelope or the publisher maps internal events to public schemas before delivery.
- Tests validate representative emitted events against the public schema.
- Docs no longer claim unavailable mappings.

### R6: Resolve balance bucket contract

Problem: `pending_cents` and `blocked_cents` are exposed and snapshotted but never maintained.

Acceptance:

- Either implement real transitions for pending/blocked balances, or remove them from public/API/operator surfaces until implemented.
- Database consistency checks and snapshots reflect the chosen contract.
- Tests prove the exposed balance response cannot imply maintained state that does not exist.

### R7: Correct API/OpenAPI drift

Problem: OpenAPI marks required idempotency keys as optional and advertises MED accept/reject success paths that runtime blocks.

Acceptance:

- OpenAPI marks write-command idempotency as required where runtime requires it.
- OpenAPI includes documented `400`, `403`, and `409` responses for relevant commands.
- MED accept/reject docs either document current forbidden behavior or the implementation is completed.
- Error docs include all runtime error codes.
- OpenAPI lint/parse passes.

### R8: Protect PII in public/API/storage surfaces

Problem: serializers, idempotency replay storage, ops pages, and logs can expose raw PII.

Acceptance:

- Public API serializers mask or scope sensitive fields.
- Idempotency response persistence does not retain unnecessary raw PII indefinitely.
- Ops views mask PII by default or require explicit privilege.
- Tests cover masking/redaction behavior.

### R9: Fix consistency tools that can write stale state

Problem: rebuilders/snapshot/reconciliation tools read ledger/projection state outside strong transactional consistency.

Acceptance:

- Balance projection rebuild applies inside a transaction after locking the target projection and recalculating inside the lock.
- Balance snapshots read projection and ledger values within a consistent per-wallet transaction or documented isolation boundary.
- Reconciliation snapshots use a consistent cutoff/isolation strategy or document asynchronous semantics clearly.
- Tests cover the rebuilder stale-write prevention path.

### R10: Harden operational and readiness surfaces

Problem: readiness leaks database exception messages; ops console reads globally with role-only access and exposes PII.

Acceptance:

- `/ready` returns generic failure details and logs internals server-side.
- Ops dashboard/wallet/Pix/audit pages have clear global-admin semantics or organization scoping.
- PII display is masked where full value is not required.

### R11: Fix performance and concurrency smells

Problem: balance projection application and wallet liability lookup can produce avoidable N+1 queries; multi-wallet money movement does not pre-lock projections deterministically.

Acceptance:

- Journal posting preloads or batches balance projections where practical.
- Multi-wallet commands lock involved wallet projections in deterministic order.
- Tests cover inverse concurrent transfer or equivalent deadlock-sensitive scenario.

### R12: Reduce misleading showpiece/docs debt

Problem: docs and code structure overstate readiness and mix ops tooling into product services.

Acceptance:

- Remove or rewrite `senior-tech-lead-validation` style self-grading.
- Move or clearly namespace database ops tooling if practical without destabilizing autoload.
- Add an `ApplicationService`/callable abstraction only if it reduces duplication without obscuring services.
- Split giant tests or services only where changes reduce real maintenance risk.

## Execution Journal Link

Detailed running journal: `docs/architecture/public-release-remediation-journal.md`.
