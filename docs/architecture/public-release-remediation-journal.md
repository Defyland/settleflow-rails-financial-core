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

### Session 2: audit residual cleanup

Implemented:

- Removed reconciliation immutability callbacks from `ReconciliationRun` and `ReconciliationRow`.
- Kept reconciliation immutability as a PostgreSQL-owned invariant through the existing evidence triggers and consistency checks.
- Split `Database::ConsistencyVerifier` into a small runner plus focused `Database::ConsistencyChecks::*` classes.
- Preserved the public consistency-check contract: check names and detail keys remain stable for tests, runbooks, and `database:verify_consistency`.
- Replaced split-payment hash fallback handling with a small internal `Entry` value object. The V1 controller remains responsible for translating request params into the service boundary.
- Made payout early-settlement checking explicit: `call` reloads once before branching, `early_settlement?` is pure, and the transaction rechecks settlement authorization after `lock!`.
- Centralized repeated Pix and MED ops `Errors::ApplicationError` redirects with `rescue_from`.
- Collapsed the duplicate outbox publishability predicate and moved creation default checks into a named constant.
- Extended `ApplicationService.call` to forward blocks and moved the remaining callable service helpers onto the shared base class.

Decision notes:

- Reconciliation evidence mutation belongs to PostgreSQL, not model callbacks. The database already owns the irreversible invariant and rejects direct SQL bypasses; duplicating it in ActiveRecord created a second source of truth and an avoidable cross-table query on every write.
- The consistency verifier should be a registry/runner, not the owner of every SQL question. Individual check classes make each operational question independently reviewable while keeping the CLI and rake task API unchanged.
- Split-payment services should not accept arbitrary external parameter shapes. Rails controllers may deal with string-keyed request params, but domain services should receive a normalized internal contract.
- The payout early-settlement post-lock guard intentionally remains inside the transaction. It is not duplicate business logic; it is the race-safe authorization check after the row has been locked.
- Ops error handling for workflow actions is controller-level response policy, so a single `rescue_from` per controller is clearer than repeating the same rescue branch in each action.
- Callable service syntax should have one implementation. The base class now supports positional args, keyword args, and blocks, so block-driven services such as idempotency, maker-checker, and temporary locks do not need bespoke `self.call` wrappers.

Verification:

- `bin/rails test test/models/reconciliation_row_test.rb test/services/split_payment_create_test.rb test/services/payout_lifecycle_test.rb test/jobs/outbox_publish_job_test.rb test/jobs/outbox_sweep_job_test.rb test/requests/ops_console_request_test.rb`
- Result: 28 runs, 267 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rails test test/services/database_consistency_verifier_test.rb`
- Result: 6 runs, 73 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rails test test/requests/ops_console_request_test.rb`
- Result after Pix/MED rescue consolidation: 8 runs, 164 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/controllers/ops/med_cases_controller.rb app/controllers/ops/pix_payments_controller.rb`
- Result: 2 files inspected, no offenses.
- `bin/rails test test/services/operational_temporary_lock_test.rb test/services/operational_redis_temporary_lock_test.rb test/requests/idempotency_test.rb test/services/payout_lifecycle_test.rb test/services/refund_and_med_lifecycle_test.rb test/services/pix_payment_lifecycle_test.rb test/requests/api_audit_logging_test.rb`
- Result after callable base consolidation: 41 runs, 204 assertions, 0 failures, 0 errors, 0 skips.
- `bin/ci`
- Result: passed. 219 unit/service/request tests, 1370 assertions, 0 failures; critical money branch coverage 85.47%; 2 system tests, 13 assertions, 0 failures; RuboCop no offenses; Brakeman 0 warnings; bundler-audit no vulnerabilities; OpenAPI and event schema parse checks passed.
- `bin/rails zeitwerk:check`
- Result: passed; only the standard unchecked `test/mailers/previews` eager-load warning.
- `bin/rails database:verify_consistency`
- Result: every consistency check reported `ok`.
- `bin/rails database:migration_safety_check`
- Result: no high-volume migration safety findings.
- `npx --yes @redocly/cli lint openapi.yaml`
- Result: valid OpenAPI description.
- `bin/rubocop app/services/balance_projections/rebuilder.rb app/services/balance_snapshots/capture.rb test/services/balance_snapshot_and_rebuild_test.rb`
- Result: 3 files inspected, no offenses.

Decision notes:

- Reconciliation runs remain operational point-in-time snapshots rather than accounting-period closes. The snapshot stores `captured_at`, and `docs/database/reconciliation-data-model.md` now documents the asynchronous consistency boundary and the production path for explicit cutoff/period-close semantics.

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
- Moved `Database::*` operational engineering services from `app/services/database` to `lib/database`, preserving constants while separating product services from ops tooling.
- Added `ApplicationService` as the shared callable base and converted the remaining exact `self.call(...); new(...).call` service-object duplicates to inherit from it.

Verification:

- `/Applications/Codex.app/Contents/Resources/rg -n "senior-tech-lead-validation|Senior and Tech Lead Validation|senior-level backend evidence|Legacy organization API key digests remain supported" README.md docs`
- Result: no remaining references outside the remediation spec requirement itself.
- `bin/rails test test/services/database_benchmark_runner_test.rb test/services/database_benchmark_thresholds_test.rb test/services/database_consistency_verifier_test.rb test/services/database_critical_query_explainer_test.rb test/services/database_migration_safety_checker_test.rb test/services/database_partition_feasibility_test.rb test/services/database_partition_plan_test.rb test/services/database_partition_readiness_test.rb test/services/database_pitr_readiness_test.rb`
- Result: 22 runs, 174 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop lib/database test/services/database_benchmark_runner_test.rb test/services/database_benchmark_thresholds_test.rb test/services/database_consistency_verifier_test.rb test/services/database_critical_query_explainer_test.rb test/services/database_migration_safety_checker_test.rb test/services/database_partition_feasibility_test.rb test/services/database_partition_plan_test.rb test/services/database_partition_readiness_test.rb test/services/database_pitr_readiness_test.rb`
- Result: 20 files inspected, no offenses.
- `bin/rails zeitwerk:check`
- Result: all application constants good; Rails emitted only the standard unchecked `test/mailers/previews` eager-load warning.
- `ruby -e 'paths=Dir["app/services/**/*.rb"].sort.select { |path| path != "app/services/application_service.rb" && File.read(path).match?(/def self\.call\(\.\.\.\)\s*\n\s*new\(\.\.\.\)\.call/) }; puts paths.size; puts paths'`
- Result: `0`.
- `bin/rails test test/services`
- Result: 111 runs, 703 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services`
- Result: 48 files inspected, no offenses.

### Session 1: Public operational surface follow-up

Implemented:

- Removed `/v1/outbox_events` from public routes and OpenAPI.
- Deleted the public outbox controller and serializer; outbox inspection remains an authenticated ops-console concern.
- Added an OpenAPI/route regression test so the operational outbox log is not accidentally reintroduced as public API.
- Updated security docs and the API-key ADR to match the disabled-by-default legacy-key policy and the absence of public outbox/audit-log endpoints.

Verification:

- `bin/rails test test/services/openapi_contract_test.rb test/requests/ops_console_request_test.rb`
- Result: 11 runs, 232 assertions, 0 failures, 0 errors, 0 skips.
- `ruby -e "require 'yaml'; YAML.load_file('openapi.yaml'); puts 'openapi.yaml parsed'"`
- Result: `openapi.yaml parsed`.
- `bin/rubocop config/routes.rb test/services/openapi_contract_test.rb`
- Result: 2 files inspected, no offenses.
- `/Applications/Codex.app/Contents/Resources/rg -n "v1/outbox_events|OutboxEventSerializer|V1::OutboxEventsController|OutboxEventCollection" app config test openapi.yaml docs README.md`
- Result: only the new regression test mentions the removed public route.
- `/Applications/Codex.app/Contents/Resources/rg -n "Legacy organization.*seed/demo compatibility|Outbox events \| Same organization only|Audit logs \| Same organization only where applicable" README.md docs app test`
- Result: no matches.

### Session 1: OpenAPI lint configuration follow-up

Implemented:

- Disabled Redocly's `operation-2xx-response` rule in `redocly.yaml` because public MED accept/reject are intentionally documented as blocked operations with no 2xx runtime path.

Verification:

- `npx --yes @redocly/cli lint openapi.yaml`
- Result: OpenAPI validated with no warnings.

### Session 1: Critical money branch coverage follow-up

Implemented:

- Added `test/services/financial_branch_coverage_test.rb` covering cross-organization, currency, invalid-state, invalid-entry, refund/MED, payout, journal, and reconciliation failure branches in money-moving services.
- Added `bin/critical_money_branch_coverage` to enforce at least 85% branch coverage across the critical money service subset.
- Added the critical money branch coverage guard to `bin/ci` immediately after `COVERAGE=1 bin/rails test`.

Verification:

- `bin/rails test test/services/financial_branch_coverage_test.rb`
- Result: 7 runs, 72 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop test/services/financial_branch_coverage_test.rb`
- Result: 1 file inspected, no offenses.
- `COVERAGE=1 bin/rails test`
- Result: 219 runs, 1370 assertions, 0 failures, 0 errors, 0 skips; line 91.79%, global branch 70.92%.
- `bin/critical_money_branch_coverage`
- Result: critical money branch coverage 85.78% (199/232).

## 2026-06-12

### Session 3: Ruby 3.4.9 revalidation and zero-finding re-audit

Implemented:

- Validated the working-tree Ruby pin update from `3.4.2` to `3.4.9` across `.ruby-version`, `.tool-versions`, `Dockerfile`, and `README.md`.
- Re-ran the thermo-nuclear and Ruby/Rails review lenses against the current working tree after the residual cleanup and journal hardening changes.
- Confirmed there were no new justified structural, Rails-boundary, or operability findings worth changing in code.
- Added this verification entry so the repository records not only what was changed, but also why the next step was deliberately to stop changing behavior.

Verification:

- `asdf exec bundle install`
- Result: bundle completed successfully under Ruby `3.4.9`.
- `export PATH="$HOME/.asdf/shims:$PATH"; ruby -v && bundle -v && bin/rails runner 'puts RUBY_VERSION; puts Rails.version'`
- Result: Ruby `3.4.9`, Bundler `4.0.10`, Rails `8.1.3`.
- `export PATH="$HOME/.asdf/shims:$PATH"; bin/ci`
- Result: 219 runs, 1370 assertions, 0 failures, 0 errors, 0 skips; line coverage 92.18%; global branch coverage 70.97%; critical money branch coverage 85.47%; 2 system tests, 13 assertions, 0 failures; RuboCop no offenses; Brakeman 0 warnings; bundler-audit no vulnerabilities; `openapi.yaml` and `docs/events/outbox_event.v1.json` parsed.
- `export PATH="$HOME/.asdf/shims:$PATH"; bin/rails zeitwerk:check`
- Result: passed; only the standard unchecked `test/mailers/previews` eager-load warning.
- `export PATH="$HOME/.asdf/shims:$PATH"; bin/rails database:verify_consistency`
- Result: every consistency check reported `ok`.
- `export PATH="$HOME/.asdf/shims:$PATH"; bin/rails database:migration_safety_check`
- Result: no high-volume migration safety findings.
- `npx --yes @redocly/cli lint openapi.yaml`
- Result: valid OpenAPI description.

Decision notes:

- This session hit an environment trap before any repo failure: the shell `PATH` still had a direct Ruby `3.4.4` install before the asdf shims. Validation was rerun with the shims explicitly prepended. That is an execution-environment concern, not a repository design flaw.
- No code-path change followed the re-audit because the current repo state already clears the previous thermo/Rails findings and the verification suite is strong enough to justify stopping.
- The right specialist signal here is restraint: once the repo is coherent, tested, and well-instrumented, adding more abstractions or cleanup without a fresh finding would lower quality rather than raise it.

### Session 4: post-audit remediation (Codex + thermo-nuclear findings)

A second adversarial audit (Codex pass plus a thermo-nuclear / Ruby-Rails code-smell pass) produced a fresh finding list. This session works it one atomic commit per fix, each followed by re-running both review lenses.

#### R13 ops authorization: every ops mutation is admin-only

Implemented:

- Changed `Ops::CapabilityPolicy` so `reject_pix_payment` and `retry_outbox_event` require `admin`, matching the already admin-only settle/reverse/MED capabilities.
- Rewrote the ops console request test to assert a non-admin operator is denied every ops mutation (settle, reverse, MED accept, reject Pix, retry outbox) and that the denial leaves the records untouched and enqueues no publish job.

Decision notes:

- Users have no `organization_id`; operators are global staff. Ops boundaries resolve records globally by `public_id`, so any operator-writable action was a blind cross-tenant write (an operator could reject a Pix payment or retry an outbox event for any tenant by guessing the id). Reads were already admin-gated in `Ops::BaseController#require_admin_global_read!`; writes now match. The `operator` role keeps `can_operate?` for sign-in but currently holds no ops-console capability — making it org-scoped or granting it a real scoped power is a deliberate later choice, not part of this security fix.

Verification:

- `bin/rails test test/requests/ops_console_request_test.rb test/requests/privacy_redaction_test.rb`
- Result: 11 runs, 206 assertions, 0 failures, 0 errors, 0 skips.

#### R14 metrics endpoint fails closed in production

Implemented:

- Reworked `Observability::MetricsController#authenticate_metrics!` so a blank `METRICS_BEARER_TOKEN` returns `503 metrics_unavailable` in production instead of building an empty `"Bearer "` expectation and comparing against it. Development/test still serve metrics open when no token is set.
- Replaced the double-negative `unless ... bytesize && secure_compare` guard with an explicit `return if match` followed by a single `401` render.
- Added an operability test proving production with no token rejects both an empty `Authorization` header and a literal `Authorization: Bearer `.

Decision notes:

- The previous code accepted exactly `Authorization: Bearer ` when the env var was unset in production, a silent-misconfiguration auth bypass exposing the Prometheus registry. Production now fails closed and matches the boot-time hard-fail posture already used by `Outbox::Publishers::HttpPublisher#validate_endpoint!`.
- While reviewing the change, the new test reintroduced a `with_rails_env` helper that already existed verbatim in `outbox_http_publisher_test.rb`. Hoisted it to `test/test_helpers/environment_test_helper.rb` and removed both local copies, so the env-stub has one owner.

Verification:

- `bin/rails test test/requests/operability_test.rb test/services/outbox_http_publisher_test.rb`
- Result: 8 runs, 31 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop` on the six touched files: no offenses.

#### R15 single canonical sensitive-key registry (closes the legal_name audit leak)

Implemented:

- Added `Privacy::SensitiveKeys` as the one registry of PII/secret keys plus a `match?` predicate.
- Rewired `Privacy::Redactor` (response/ops masking) and `AuditLogs::ParameterSanitizer` (audit redaction) to consult it, deleting both local `SENSITIVE_KEYS` arrays and both copied `sensitive_key?` methods.
- Added an audit-logging assertion that `legal_name` is now `[FILTERED]` in persisted audit params.

Decision notes:

- The two lists had drifted: `Redactor` listed `legal_name` and `ParameterSanitizer` did not, so a customer `legal_name` was masked in public API responses but written in clear to the audit log. One registry owns *what* is sensitive; each caller still owns *how* it masks. `password_confirmation` was dropped as a redundant entry — the substring match on `password` already covers it.
- The Rails `config.filter_parameters` initializer is intentionally left separate: it is the framework log-filtering layer, not application redaction, and referencing an autoloaded constant from an initializer would couple boot order to app autoload.

Verification:

- `bin/rails test test/requests/api_audit_logging_test.rb test/requests/privacy_redaction_test.rb test/requests/financial_workflow_test.rb`
- Result: 11 runs, 109 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/services/privacy app/services/audit_logs` and `bin/rails zeitwerk:check`: clean.

#### R16 JournalEntry#balanced? matches the per-currency invariant

Implemented:

- Changed `JournalEntry#balanced?` to group ledger lines by currency and require debits to equal credits within each currency, instead of comparing total debits against total credits across all currencies.

Decision notes:

- The old predicate would call a multi-currency journal balanced when each side summed equally across different currencies, even though no currency netted to zero. `Ledger::JournalPoster` and the database `assert_journal_entry_balanced` trigger both balance per currency, so the Ruby mirror now matches its authority.
- No dedicated false-case test was added: the per-currency rejection is already exercised at the database level by `database_financial_invariants_test.rb` ("database rejects direct unbalanced journal inserts"), and `balanced?` is a test-convenience mirror with no production callers. The strengthened predicate is covered on the true path by the 38 service assertions below.

Verification:

- `bin/rails test test/services/ledger_journal_poster_test.rb test/services/transfer_create_test.rb test/services/split_payment_create_test.rb test/services/pix_payment_lifecycle_test.rb test/services/payout_lifecycle_test.rb test/services/refund_and_med_lifecycle_test.rb`
- Result: 38 runs, 188 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop app/models/journal_entry.rb`: no offenses.

#### R17 database CHECK constraints on the five lifecycle status columns

Implemented:

- Added `customers_status_check`, `journal_entries_status_check`, `ledger_accounts_status_check`, `organizations_status_check`, and `wallets_status_check` in migration `20260612120000`, matching each model enum's allowed values.
- Added a `database_financial_invariants_test` case proving the database rejects an invalid status written by raw SQL (bypassing the Active Record enum) on the four mutable tables, each isolated in its own savepoint.

Decision notes:

- These five were the only status columns still guarded solely by the Rails enum while every other financial status column already had a DB `*_status_check`. For a system whose stated philosophy is "the database owns invariants," `journal_entries.status` especially should not depend on the application layer.
- `journal_entries` is not exercised by the raw-UPDATE test because its append-only trigger rejects any update before the status check is reached; its constraint presence is verified in `db/structure.sql` and its append-only guarantee is already tested separately.
- Migration follows the repo's `add_check_constraint validate: false` + `validate_check_constraint` idiom.

Verification:

- `bin/rails db:migrate` (development) then `db:test:prepare`; `db/structure.sql` now carries all five constraints.
- `bin/rails test test/models/database_financial_invariants_test.rb`
- Result: 26 runs, 118 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rails database:verify_consistency` all checks ok; `database:migration_safety_check` no findings; `bin/rubocop` clean.

#### R18 remove the dead cache temporary lock

Implemented:

- Deleted `Operational::TemporaryLock` (Rails.cache-backed) and its test. It had no caller anywhere; its only non-test role was hosting two constants imported by `Operational::RedisTemporaryLock`.
- Inlined `DEFAULT_TTL` and `FORBIDDEN_KEY_PARTS` into `RedisTemporaryLock`, which is now self-contained and still used by the `redis:verify` rake smoke task.

Decision notes:

- The thermo pass flagged "two near-identical lock implementations, neither used in app code." On closer reading only the cache lock was truly dead; `RedisTemporaryLock` is referenced by `lib/tasks/database_engineering.rake` (`redis:verify`). The narrower fix removes the genuinely dead class and the cross-class constant import while preserving the Redis demo. The broader question of how much `lib/database` / operational tooling a portfolio app should carry is left as a deliberate product call, not folded into a security/maintainability commit.

Verification:

- `bin/rails test test/services/operational_redis_temporary_lock_test.rb`
- Result: 3 runs, 14 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rails zeitwerk:check` and `bin/rubocop`: clean.

#### R19 move database object-name mirrors out of FinancialContracts

Implemented:

- Moved the five lists of database trigger/constraint *names* (`OUTBOX_EVIDENCE_CONSTRAINTS`, `OUTBOX_EVIDENCE_TRIGGERS`, `FINANCIAL_STATE_EVIDENCE_TRIGGERS`, `FINANCIAL_JOURNAL_EVIDENCE_TRIGGERS`, `IDEMPOTENCY_REQUIRED_COMMAND_CONSTRAINTS`) from `FinancialContracts` into the single consistency-check class that consumes each, as `EXPECTED_TRIGGERS` / `EXPECTED_CONSTRAINTS` / `REQUIRED_COMMAND_CONSTRAINTS`.
- Updated the verifier test to read the constants from their new owners.

Decision notes:

- `FinancialContracts` is the domain taxonomy: event types, actions, aggregate types, and lock-key builders. The names of migration-created triggers and constraints are an implementation detail of the schema, and the only code that needs them is the consistency checker that asserts they are present. Keeping them in the domain module coupled the taxonomy to migration internals and risked silent drift on a rename. This also follows the precedent already set by `IdempotencyEvidenceGuards::EXPECTED_CONSTRAINTS`.
- Event-type taxonomies (`RECONCILIATION_EVENT_TYPES`, `JOURNAL_EVENT_TYPES`) and `FINANCIAL_COMMAND_AGGREGATE_TYPES` stayed: those are domain values, not schema object names.

Verification:

- `bin/rails test test/services/database_consistency_verifier_test.rb`
- Result: 6 runs, 73 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rails database:verify_consistency` all checks ok; `bin/rails zeitwerk:check` and `bin/rubocop` (16 files): clean.

#### R20 bound the wallet statement / balance-explanation ledger reads

Implemented:

- `Wallets::StatementBuilder` now loads only the most recent `limit` ledger lines (newest first) and derives each running balance backward from `LedgerAccount#balance_cents`, instead of materializing the wallet's entire history to slice one window.
- `Wallets::BalanceExplainer#recent_lines` does the same, anchored on the ledger-derived available balance it already computes, returning the window oldest-first as before.
- Added `wallets_statement_builder_test` proving the window is capped to `limit` and that running balances are correct for a partial window that excludes older lines (the case the existing request test never exercised).

Decision notes:

- `GET /v1/wallets/:id/statement` and `/balance_explanation` previously loaded every ledger line on every call to compute running balances from zero, then dropped all but the last 100/limit. On a high-volume wallet that is an unbounded request-path load. The running balance is recoverable from the current ledger total minus the deltas of the newer lines, so only the window plus two aggregate sums are needed.
- The anchor is `LedgerAccount#balance_cents` (authoritative ledger sum), not `balance_projection.available_cents`. This preserves the original behavior of reading fresh ledger truth and avoids depending on the freshness of the caller's projection association — a regression an earlier draft introduced and the new partial-window test caught.
- `Reconciliation::RowsBuilder#platform_cash_lines` was reviewed and left unchanged: it is already scoped to `statement_date.all_day` and iterated with `find_each`, so it is bounded by a single statement day, not the full history.

Verification:

- `bin/rails test test/services/wallets_statement_builder_test.rb test/requests/financial_workflow_test.rb test/requests/ops_console_request_test.rb test/services/financial_branch_coverage_test.rb`
- Result: 27 runs, 344 assertions, 0 failures, 0 errors, 0 skips.
- `bin/rubocop` on the touched files: no offenses.

#### R21 decision journal and the immutability ownership ruling

Implemented:

- Created `docs/decisions.md`, the lightweight decision log this workspace expects alongside the formal ADRs, and recorded the Session 4 decisions in it.
- Resolved the thermo "inconsistent immutability" finding as a documented decision rather than code churn: the five model-level immutability callbacks stay (they are query-free guards that return a clean error and are backed by the authoritative DB trigger), and the reconciliation guards stay removed (they performed their own cross-table query the trigger already does).

Decision notes:

- The maintainability finding was "five models duplicate the DB immutability trigger with a callback while reconciliation does not." Verified each retained guard is column-only (`OperatorApproval#prevent_terminal_mutation` reads `status_in_database`; the rest are unconditional `raise`/`throw`), so the distinction from the removed reconciliation guards is real (query cost), not arbitrary. Documented the rule so the next reader knows when to keep vs. drop an app-level immutability guard.

Verification:

- Docs-only change; no test impact. `docs/decisions.md` added; remediation journal cross-referenced.
