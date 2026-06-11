# Public Release Remediation Journal

## 2026-06-11

### Session 1: Baseline and spec

- Confirmed working tree is clean before remediation.
- Confirmed there is no project-local `AGENTS.md` inside `settleflow-rails-financial-core`; global workspace rules apply.
- Confirmed current architecture is Rails 8.1, Minitest, SQL schema, and existing financial database invariants.
- Created this journal and the remediation spec to turn audit findings into traceable requirements.

Initial requirement order:

1. R1 domain-state enforcement.
2. R2 API credential/legacy-key hardening.
3. R3 audit accuracy and PII sanitization.
4. R4 outbox reliability.
5. R5 event contract alignment.
6. R6 balance bucket contract.
7. R7 API/OpenAPI drift.
8. R8 PII/idempotency/ops masking.
9. R9 consistency tools.
10. R10 operational surfaces.
11. R11 performance/concurrency smells.
12. R12 docs/maintainability cleanup.

Commit plan:

- Commit spec/journal first.
- Then implement one remediation unit per commit, each with focused tests before broader verification.

### Session 1: R1 domain-state enforcement

Implemented:

- Added `FinancialLifecycle::StatusGuard` as the single service-level guard for lifecycle state.
- Funding now rejects blocked/closed wallets before ledger mutation.
- Transfer now rejects inactive source and destination wallets.
- Pix payment creation now rejects inactive wallets before creating Pix state.
- Payout creation now rejects inactive wallets.
- Split payments now reject inactive source and destination wallets.
- Refund creation and direct Pix reversal now reject inactive wallet-crediting paths.
- Wallet creation now rejects blocked/closed customers.

Verification:

- `bin/rails test test/services/funding_create_test.rb test/services/transfer_create_test.rb test/services/pix_payment_lifecycle_test.rb test/services/payout_lifecycle_test.rb test/services/split_payment_create_test.rb test/services/refund_and_med_lifecycle_test.rb test/services/wallet_creator_test.rb`
- Result: 35 runs, 183 assertions, 0 failures, 0 errors, 0 skips.

Decision notes:

- Existing settlement jobs (`PixPayments::Settle`, `Payouts::Settle`) were not blocked by later wallet status changes because the wallet balance was already debited before settlement. Blocking settlement would strand clearing balances rather than protect customer funds.

### Session 1: R2 API credential and seed hardening

Implemented:

- Added `config.x.api.allow_legacy_organization_api_keys`, defaulting to `false`.
- Enabled legacy organization API keys only in development/test compatibility configuration.
- Updated V1 authentication so `Organization.authenticate_api_key` is not consulted when the compatibility flag is disabled.
- Added an integration test proving a legacy organization API key is rejected when compatibility is disabled.
- Changed seeds to create a scoped `ApiCredential` for the demo organization instead of publishing a known organization-level API key.
- Removed known default API key/password values from `.env.example`, README, API examples, and benchmark docs.
- Made demo seeds refuse non-development/test execution unless explicitly allowed.

Verification:

- `bin/rails test test/requests/api_authentication_test.rb`
- Result: 6 runs, 13 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rails runner -e test 'ActiveRecord::Base.transaction(requires_new: true) { load Rails.root.join("db/seeds.rb"); raise ActiveRecord::Rollback }'`
- Result: passed.
- `bin/rubocop app/controllers/v1/base_controller.rb config/application.rb config/environments/development.rb config/environments/test.rb db/seeds.rb test/requests/api_authentication_test.rb`
- Result: 6 files inspected, no offenses.

### Session 1: R3 audit accuracy and sanitization

Implemented:

- Added `AuditLogs::ParameterSanitizer` for audit-specific recursive redaction.
- Added `AuditLogs::RequestLogger` to centralize API audit writes and swallow audit-store failures after logging them.
- Changed V1 request auditing so normal audit writes are skipped when the action raises; the existing `rescue_from` path writes one error audit with the final status and error code.
- Changed success and error audit metadata to use sanitized params.
- Extended Rails parameter filtering for financial PII keys.

Verification:

- `bin/rails test test/requests/api_audit_logging_test.rb test/requests/api_authentication_test.rb test/requests/financial_workflow_test.rb`
- Result: 14 runs, 77 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services/audit_logs/parameter_sanitizer.rb app/services/audit_logs/request_logger.rb app/controllers/v1/base_controller.rb app/controllers/api_controller.rb config/initializers/filter_parameter_logging.rb test/requests/api_audit_logging_test.rb`
- Result: 6 files inspected, no offenses.

Decision notes:

- Unhandled non-application exceptions are not force-audited in the around action. That avoids writing false `200` audit records before Rails has mapped the exception. Rescuable API errors are audited through `render_application_error`.

### Session 1: R4 transactional outbox reliability

Implemented:

- Split `OutboxPublishJob` into a publish phase and a post-publish analytics enqueue phase.
- Publish failures still mark the event pending/dead-lettered and schedule retry.
- Analytics enqueue failures now log `outbox.analytics_enqueue_failed` but do not revert a published event to `pending`.
- Added `OutboxSweepJob` to enqueue `OutboxEvent.publishable` records.
- Added production recurring schedule for the sweep job.

Verification:

- `bin/rails test test/jobs/outbox_publish_job_test.rb test/jobs/outbox_sweep_job_test.rb`
- Result: 9 runs, 39 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/jobs/outbox_publish_job.rb app/jobs/outbox_sweep_job.rb test/jobs/outbox_publish_job_test.rb test/jobs/outbox_sweep_job_test.rb`
- Result: 4 files inspected, no offenses.

Decision notes:

- The sweep job intentionally re-enqueues publish jobs instead of publishing inline. Claiming and state transition remain centralized in `OutboxPublishJob`.
- Tests isolate existing pending events by pushing their retry time into the future rather than falsifying published state, because database checks require real publication evidence for `published` events.

### Session 1: R5 event contract alignment

Implemented:

- Removed stale per-event JSON schemas that described a snake_case external taxonomy the application did not publish.
- Added `docs/events/outbox_event.v1.json`, matching the actual envelope emitted by `Outbox::Publisher.envelope_for`.
- Rewrote `docs/events/README.md` around the real outbox envelope and current `FinancialContracts::Events` taxonomy.
- Updated messaging docs to remove the claim that publishers map internal events to a separate public taxonomy.
- Updated local and GitHub event-contract checks so they validate an event-type `const` or `enum` contract and a payload contract.
- Added an outbox contract test that compares schema event types to `FinancialContracts::Events` and validates representative real envelopes.

Verification:

- `bin/rails test test/services/outbox_event_contract_test.rb`
- Result: 4 runs, 49 assertions, 0 failures, 0 errors, 0 skips.
- `ruby -rjson -e 'Dir["docs/events/*.v1.json"].sort.each { |path| schema = JSON.parse(File.read(path)); event_type = schema.dig("properties", "event_type"); abort("#{path}: event_type contract missing") unless event_type&.key?("const") || event_type&.key?("enum"); payload = schema.dig("properties", "payload"); abort("#{path}: payload contract missing") unless payload.is_a?(Hash); puts "#{path} parsed" }'`
- Result: `docs/events/outbox_event.v1.json parsed`.
- `bin/rubocop test/services/outbox_event_contract_test.rb`
- Result: 1 file inspected, no offenses.

Decision notes:

- Chose to document the actual emitted envelope instead of introducing a mapping layer. A separate external taxonomy can be added later, but only with a publisher mapper and schema validation tests in the same change.

### Session 1: R6 balance bucket contract

Implemented:

- Removed `pending_cents` and `blocked_cents` from the public balance serializer.
- Removed `pending_cents` and `blocked_cents` from the OpenAPI `Balance` response schema.
- Removed pending/blocked metrics from the ops wallet detail page.
- Added a request assertion proving balance responses no longer expose those buckets.

Verification:

- `bin/rails test test/requests/financial_workflow_test.rb test/requests/ops_console_request_test.rb`
- Result: 12 runs, 207 assertions, 0 failures, 0 errors, 0 skips.
- `ruby -e "require 'yaml'; YAML.load_file('openapi.yaml'); puts 'openapi.yaml parsed'"`
- Result: `openapi.yaml parsed`.
- `bin/rubocop app/serializers/balance_projection_serializer.rb test/requests/financial_workflow_test.rb`
- Result: 2 files inspected, no offenses.

Decision notes:

- Kept the database columns and snapshot fields as internal storage/invariant surface for now. The remediation removes the misleading API and operator promise until real pending/blocked transitions exist.

### Session 1: R7 API/OpenAPI drift

Implemented:

- Marked the shared OpenAPI `Idempotency-Key` parameter as required.
- Added documented `400` and `409` responses to all idempotent public write commands.
- Added documented `403` responses where runtime authorization blocks public writes.
- Changed MED accept/reject OpenAPI docs to describe the actual public behavior: terminal resolution is forbidden and requires ops maker-checker approval.
- Removed false `200` success responses from public MED accept/reject.
- Added missing error-format docs for `authorization_failed` and `idempotency_key_required`.
- Added an OpenAPI contract test for idempotency response documentation and MED forbidden behavior.

Verification:

- `bin/rails test test/services/openapi_contract_test.rb test/requests/financial_extensions_api_test.rb`
- Result: 3 runs, 85 assertions, 0 failures, 0 errors, 0 skips.
- `ruby -e "require 'yaml'; YAML.load_file('openapi.yaml'); puts 'openapi.yaml parsed'"`
- Result: `openapi.yaml parsed`.
- `bin/rubocop test/services/openapi_contract_test.rb`
- Result: 1 file inspected, no offenses.
- `ruby -ryaml -e 'doc=YAML.load_file("openapi.yaml"); doc["paths"].each { |path, ops| ops.each { |method, spec| next unless method == "post"; puts "#{path}: #{spec.fetch("responses").keys.join(",")}" } }'`
- Result: every POST with `Idempotency-Key` documents `400` and `409`; MED accept/reject document `400,403,409` and no `200`.

### Session 1: R8 PII redaction and idempotency evidence

Implemented:

- Added `Privacy::Redactor` for public response and ops-display redaction.
- Redacted sensitive customer, Pix, payout, and metadata fields in public serializers.
- Redacted serializer metadata broadly by returning a `{ redacted: true }` marker for non-empty metadata.
- Stored sanitized idempotency response bodies instead of raw response bodies.
- Masked default ops wallet and Pix PII displays.
- Added request tests proving API responses, persisted idempotency evidence, and ops HTML do not expose raw PII.

Verification:

- `bin/rails test test/requests/privacy_redaction_test.rb test/requests/idempotency_test.rb test/requests/pix_payments_api_test.rb test/requests/financial_workflow_test.rb test/requests/ops_console_request_test.rb`
- Result: 24 runs, 275 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services/privacy/redactor.rb app/helpers/application_helper.rb app/services/idempotency/runner.rb app/serializers test/requests/privacy_redaction_test.rb`
- Result: 21 files inspected, no offenses.

Decision notes:

- This change redacts by default because the API has no field-level privilege model. Full PII can be added later through explicit privileged endpoints/scopes rather than accidental default serializers.

### Session 1: R9 consistency tools

Implemented:

- Changed `BalanceProjections::Rebuilder` so `apply: true` locks the projection first, then recalculates the ledger balance inside the transaction before writing.
- Added a regression test proving apply mode does not use the stale dry-run balance when the ledger value changes between calculation and lock.
- Changed `BalanceSnapshots::Capture` to capture each wallet inside a transaction after locking its projection, so projection and ledger comparison are read within a single per-wallet boundary.

Verification:

- `bin/rails test test/services/balance_snapshot_and_rebuild_test.rb test/services/database_consistency_verifier_test.rb`
- Result: 9 runs, 89 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services/balance_projections/rebuilder.rb app/services/balance_snapshots/capture.rb test/services/balance_snapshot_and_rebuild_test.rb`
- Result: 3 files inspected, no offenses.

Decision notes:

- Reconciliation snapshot isolation remains a larger semantic decision. This pass fixed the concrete stale-write path and the daily balance snapshot read boundary without changing reconciliation output semantics.

### Session 1: R10 operational surfaces

Implemented:

- Changed `/ready` failure responses to return a generic `database: failed` value while logging the internal exception server-side.
- Added admin-only protection for global ops read surfaces (`index`/`show`) through `Ops::BaseController`.
- Preserved non-read operational actions under existing capability checks.
- Added tests for readiness error redaction and non-admin global ops read denial.

Verification:

- `bin/rails test test/requests/operability_test.rb test/requests/ops_console_request_test.rb`
- Result: 12 runs, 176 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/controllers/health/readiness_controller.rb app/controllers/ops/base_controller.rb test/requests/operability_test.rb test/requests/ops_console_request_test.rb`
- Result: 4 files inspected, no offenses.

### Session 1: R11 performance and concurrency

Implemented:

- Added `Wallets::ProjectionLocker` to lock wallet balance projections in deterministic `wallet_id` order.
- Updated transfers to lock both source and destination wallet projections before the funds check and ledger post.
- Updated split payments to lock source and destination wallet projections before the funds check and ledger post.
- Added a regression test that posts inverse transfers concurrently and proves both complete without deadlock or balance drift.
- Changed `Ledger::JournalPoster` to batch-load balance projections and apply one net delta per wallet/currency instead of looking up a projection for every ledger line.
- Changed `Wallet#liability_account` to reuse preloaded/memoized ledger accounts.
- Added a regression test covering multiple same-wallet lines that collapse into a net projection delta.

Verification:

- `bin/rails test test/services/financial_concurrency_test.rb test/services/transfer_create_test.rb test/services/split_payment_create_test.rb`
- Result: 12 runs, 66 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services/wallets/projection_locker.rb app/services/transfers/create.rb app/services/split_payments/create.rb test/services/financial_concurrency_test.rb`
- Result: 4 files inspected, no offenses.
- `bin/rails test test/services/ledger_journal_poster_test.rb test/services/transfer_create_test.rb test/services/split_payment_create_test.rb test/services/financial_concurrency_test.rb`
- Result: 19 runs, 88 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services/ledger/journal_poster.rb app/models/wallet.rb test/services/ledger_journal_poster_test.rb`
- Result: 3 files inspected, no offenses.

Decision notes:

- The helper locks projections instead of wallets because the contested invariant is the projected liability balance, and existing money paths already use projection locking for funds checks.
- Sorting by wallet id removes opposite-order lock acquisition between inverse transfers and split destinations while keeping the change local to the current transaction-script services.
- Projection batching is kept inside `JournalPoster` because projection maintenance is a ledger side effect, not a caller responsibility.

### Session 1: R12 maintainability and public-release framing

Implemented:

- Removed the self-validating `docs/architecture/senior-tech-lead-validation.md` guide.
- Removed the README link to that guide and replaced portfolio-reviewer framing with neutral backend-pattern language.
- Updated README security wording so legacy organization API keys are described as disabled-by-default development/test compatibility, matching R2.

Verification:

- `/Applications/Codex.app/Contents/Resources/rg -n "senior-tech-lead-validation|Senior and Tech Lead Validation|senior-level backend evidence|Legacy organization API key digests remain supported" README.md docs`
- Result: no remaining references outside the remediation spec requirement itself.
