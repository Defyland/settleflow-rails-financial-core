# ADR 0004: Hybrid Rails Monolith with Hotwire Ops

## Status

Accepted.

## Context

SettleFlow started as a Rails API financial core. That is appropriate for machine-to-machine integrations, but it leaves an important production concern underrepresented: internal financial operations. Real fintech platforms need operators to inspect wallet balances, ledger entries, reconciliation discrepancies, pending Pix review, outbox state, and audit evidence without calling JSON endpoints by hand.

Rails 8's default direction favors a full-stack monolith with ERB, Hotwire, Importmap, Propshaft, Solid Queue, Solid Cache, Solid Cable, Kamal, Thruster, Minitest, and framework-provided authentication. This is a good fit for an operational console around the existing core.

## Decision

SettleFlow will become a hybrid Rails monolith:

- Keep `/v1/*` as the external JSON API contract.
- Add an authenticated `/ops` backoffice rendered with ERB, Turbo, Stimulus, Importmap, and Propshaft.
- Use Rails authentication for human operators while keeping API keys for external clients.
- Use Solid Queue for jobs, Solid Cache for cache, and Solid Cable for future live updates.
- Use Minitest, fixtures, and Capybara system tests for API, domain, and Hotwire coverage.

## Consequences

- The project demonstrates Rails as a production monolith instead of a backend-only API.
- Operators get product-grade workflows without weakening the API contract.
- The project stays aligned with Rails defaults and avoids carrying two application test stacks.
- The UI must stay operational and dense, not marketing-oriented.
