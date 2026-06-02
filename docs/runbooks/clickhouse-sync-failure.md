# ClickHouse Sync Failure Runbook

ClickHouse failure is an analytics incident, not a financial correctness incident.

1. Confirm PostgreSQL `outbox_events` remain published and the database trigger is present.
2. Inspect `processed_events` with processor `clickhouse_financial_events`.
3. Check ClickHouse availability and insert errors.
4. Run `bin/rails database:verify_consistency` and confirm `processed_event_evidence_guards=ok`; do not backfill while processed-event evidence diverges from published outbox evidence.
5. Confirm `outbox_evidence_guards` reports `mutable_command_identity_mismatches=0`. Treat published legacy command-identity mismatches as historical analytics annotations, not rows to edit, because the published payload hash is terminal evidence.
6. Recreate schema if needed:

```bash
bin/rails clickhouse:create_schema
```

7. Backfill published outbox events:

```bash
bin/rails clickhouse:backfill[10000]
```

8. Compare processed event count with published outbox count.
9. If sync fails with `Processed event does not match outbox event`, preserve the row as evidence and investigate outbox/process drift before retrying.
10. Do not rewrite PostgreSQL financial rows to repair analytics.
