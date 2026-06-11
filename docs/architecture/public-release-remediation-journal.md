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
