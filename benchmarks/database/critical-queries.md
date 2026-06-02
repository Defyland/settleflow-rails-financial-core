# Critical Queries

The benchmark task captures these query families:

| Name | Purpose | Risk |
| --- | --- | --- |
| `wallet_statement` | Customer-facing and Ops statement reads | slow statements under high ledger volume |
| `reconciliation_accounts` | Platform cash, clearing, and wallet liability aggregation | full table scans during daily reconciliation |
| `outbox_publishable` | Worker queue claim candidate selection | backlog and duplicate publish risk |
| `audit_chain_tail` | Operational audit inspection | slow audit incident review |

Use `docs/database/indexing-strategy.md` when interpreting plans.
