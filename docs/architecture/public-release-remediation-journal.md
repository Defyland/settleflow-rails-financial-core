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
