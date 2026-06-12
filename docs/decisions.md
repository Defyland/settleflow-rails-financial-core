# Decision Journal

A running log of technical decisions, lighter than a formal ADR. Architectural
decisions with long-lived consequences live in [docs/adr](adr); narrower
implementation decisions are recorded here, newest first. Change-by-change
verification detail lives in
[docs/architecture/public-release-remediation-journal.md](architecture/public-release-remediation-journal.md).

## 2026-06-12 — Post-audit remediation (Codex + thermo-nuclear round)

### Model-level immutability guards are kept where they are query-free

**Context.** Five models (`LedgerLine`, `JournalEntry`, `BalanceSnapshot`,
`OperatorApproval`, `OutboxLegacyCommandIdentityException`) carry `before_update`
/ `before_destroy` immutability callbacks while the database also enforces the
same immutability through triggers. An earlier session removed the analogous
callbacks from the reconciliation models, stating that duplicating the guard in
Active Record created "a second source of truth and an avoidable cross-table
query on every write." A maintainability review flagged the remaining five as an
inconsistent application of that principle.

**Decision.** Keep the five model callbacks; do not reintroduce the reconciliation
ones.

**Rationale.** The distinction is query cost, not whim. The five retained guards
are query-free: they `raise`/`throw :abort` based only on the record's own
in-memory columns (e.g. `OperatorApproval#prevent_terminal_mutation` reads
`status_in_database`; the rest are unconditional). They cost nothing per write
and return a clear `ActiveRecord::ReadOnlyRecord` / validation error before the
statement reaches the database. The reconciliation guards that were removed
performed their own cross-table query (checking for outbox evidence) on every
write — pure duplication of work the deferred DB trigger already does. So:
keep cheap, column-only immutability guards as a fast application-level error
backed by the authoritative trigger; drop guards that need their own query.

### Every ops console mutation is admin-only

**Context.** Users have no `organization_id`; operators are global staff. Ops
boundaries resolve records globally by `public_id`. Granting `operator` the
`reject_pix_payment` / `retry_outbox_event` capabilities allowed a blind
cross-tenant write for any tenant whose id could be guessed.

**Decision.** All ops capabilities require `admin`. Reads were already admin-gated;
writes now match. The `operator` role keeps `can_operate?` for sign-in but holds
no ops-console capability today. Giving operators an organization scope or a
genuinely scoped power is a deliberate future choice, intentionally not bundled
into the security fix.

### Other decisions in this round

- **Metrics endpoint fails closed in production** when `METRICS_BEARER_TOKEN` is
  unset, instead of comparing against an empty `"Bearer "` token.
- **One sensitive-key registry** (`Privacy::SensitiveKeys`) owns *what* is
  sensitive; the audit sanitizer and response redactor own *how* they mask.
  This closed a `legal_name` leak where the two had drifted. The Rails
  `config.filter_parameters` initializer stays separate as the framework
  log-filtering layer.
- **`JournalEntry#balanced?` balances per currency**, matching `JournalPoster`
  and the database trigger rather than comparing cross-currency totals.
- **Lifecycle status columns get DB CHECK constraints** (`customers`,
  `journal_entries`, `ledger_accounts`, `organizations`, `wallets`), closing the
  last gap where a status was guarded only by the Rails enum.
- **Database trigger/constraint name lists moved out of `FinancialContracts`**
  into the consistency-check classes that consume them; the module keeps domain
  taxonomy (events, actions, aggregate types, lock keys).
- **Wallet statement / balance-explanation reads are windowed**, deriving running
  balances backward from `LedgerAccount#balance_cents` instead of loading the
  full ledger history per request.

### Deferred (product call, not taken)

- **Volume of `lib/database` tooling.** ~2,300 lines of rake-only database
  engineering (partition planning, PITR readiness, backup drills) earn their keep
  only if this repo is meant to *demonstrate* that range. Whether to keep, prune,
  or quarantine it is a portfolio/product decision, deliberately left out of the
  security/maintainability commits.
