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
