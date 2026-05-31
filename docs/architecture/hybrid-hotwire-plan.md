# Hybrid Hotwire Implementation Plan

## Goal

Add a production-oriented operations backoffice to SettleFlow while preserving the existing financial API and ledger architecture.

## Phase 1: Rails full-stack foundation

Status: complete.

- Disable API-only mode.
- Enable Action Mailer, Active Storage, and Rails test framework.
- Add Importmap, Turbo, Stimulus, Propshaft, bcrypt, Kamal, and Thruster.
- Install Solid Cache and Active Storage schemas.
- Keep API controllers inheriting from `ActionController::API` semantics where needed through explicit JSON behavior.

## Phase 2: Operator authentication

Status: complete.

- Use Rails authentication generator as the human session boundary.
- Seed a development operator through environment variables.
- Keep API key authentication for `/v1`.
- Store the current operator in `Current` only for request-scoped UI behavior.

## Phase 3: Ops backoffice

Status: complete.

- Add `/ops` dashboard with financial KPIs.
- Add ERB/Turbo views for wallets, Pix review queue, reconciliation runs, outbox events, ledger entries, and audit logs.
- Add safe operator actions for:
  - settling approved Pix payments
  - marking pending-review Pix as rejected
  - retrying pending outbox events
- Prefer read-heavy, dense screens with explicit drill-down links.

## Phase 4: Tests and production readiness

Status: complete.

- Add Minitest fixtures for users/operators and core records needed by system tests.
- Add Capybara system tests for sign-in and core backoffice navigation.
- Migrate domain, request, job, and service coverage to Minitest.
- Update CI to run Minitest, system tests, RuboCop, Brakeman, Bundler Audit, OpenAPI validation, and Docker build.

## Implemented routes

- `/ops`: financial KPIs and operational queues.
- `/ops/wallets`: wallet list and statement drill-down.
- `/ops/pix_payments`: Pix review, rejection, and settlement.
- `/ops/outbox_events`: outbox status and retry.
- `/ops/reconciliation_runs`: provider-vs-ledger differences.
- `/ops/ledger_entries`: immutable double-entry detail.
- `/ops/audit_logs`: API and operator audit trail.

## Non-goals

- Do not replace the public API with HTML.
- Do not introduce React, Vite, Sidekiq, Redis, or a separate admin service.
- Do not reintroduce a second test stack without a concrete gap in Rails defaults.
