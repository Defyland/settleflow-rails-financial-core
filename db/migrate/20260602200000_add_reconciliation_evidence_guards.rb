class AddReconciliationEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    backfill_legacy_reconciliation_rows

    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM reconciliation_runs rr
          WHERE btrim(provider) = ''
             OR status NOT IN ('matched', 'discrepant')
             OR discrepancy_cents <> provider_balance_cents - ledger_balance_cents
             OR NOT EXISTS (
               SELECT 1
               FROM outbox_events oe
               WHERE oe.aggregate_type = 'ReconciliationRun'
                 AND oe.aggregate_id = rr.id
                 AND oe.event_type IN ('reconciliation.matched', 'reconciliation.discrepant')
             )
             OR NOT EXISTS (
               SELECT 1
               FROM reconciliation_rows row
               WHERE row.reconciliation_run_id = rr.id
             )
             OR (status = 'matched' AND EXISTS (
               SELECT 1
               FROM reconciliation_rows row
               WHERE row.reconciliation_run_id = rr.id
                 AND row.status <> 'matched'
             ))
             OR (status = 'discrepant' AND NOT EXISTS (
               SELECT 1
               FROM reconciliation_rows row
               WHERE row.reconciliation_run_id = rr.id
                 AND row.status <> 'matched'
             ))
        ) THEN
          RAISE EXCEPTION 'existing reconciliation_runs violate evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1
          FROM reconciliation_rows row
          LEFT JOIN reconciliation_runs run ON run.id = row.reconciliation_run_id
          LEFT JOIN journal_entries journal ON journal.id = row.journal_entry_id
          WHERE run.id IS NULL
             OR run.organization_id <> row.organization_id
             OR (journal.id IS NOT NULL AND journal.organization_id <> row.organization_id)
             OR (row.status = 'matched' AND row.difference_cents <> 0)
             OR (row.status = 'discrepant' AND row.difference_cents = 0)
             OR (row.status = 'missing_in_ledger' AND (row.ledger_amount_cents <> 0 OR row.provider_amount_cents = 0))
             OR (row.status = 'missing_in_provider' AND (row.provider_amount_cents <> 0 OR row.ledger_amount_cents = 0))
        ) THEN
          RAISE EXCEPTION 'existing reconciliation_rows violate evidence guards';
        END IF;
      END
      $$;
    SQL

    add_check_constraint :reconciliation_runs, "btrim(provider) <> ''", name: "reconciliation_runs_provider_present_check", validate: false
    add_check_constraint :reconciliation_runs, "status IN ('matched', 'discrepant')", name: "reconciliation_runs_status_check", validate: false
    add_check_constraint :reconciliation_runs,
      "discrepancy_cents = provider_balance_cents - ledger_balance_cents",
      name: "reconciliation_runs_discrepancy_check",
      validate: false
    add_check_constraint :reconciliation_rows, reconciliation_row_amount_status_check, name: "reconciliation_rows_amount_status_check", validate: false
    validate_check_constraint :reconciliation_runs, name: "reconciliation_runs_provider_present_check"
    validate_check_constraint :reconciliation_runs, name: "reconciliation_runs_status_check"
    validate_check_constraint :reconciliation_runs, name: "reconciliation_runs_discrepancy_check"
    validate_check_constraint :reconciliation_rows, name: "reconciliation_rows_amount_status_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION reconciliation_run_has_outbox_evidence(run_id_to_check bigint)
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM outbox_events
          WHERE aggregate_type = 'ReconciliationRun'
            AND aggregate_id = run_id_to_check
            AND event_type IN ('reconciliation.matched', 'reconciliation.discrepant')
        );
      $$;

      CREATE OR REPLACE FUNCTION assert_reconciliation_run_evidence(run_id_to_check bigint)
      RETURNS void
      LANGUAGE plpgsql
      AS $$
      DECLARE
        run_row reconciliation_runs%ROWTYPE;
      BEGIN
        SELECT * INTO run_row
        FROM reconciliation_runs
        WHERE id = run_id_to_check;

        IF run_row.id IS NULL THEN
          RETURN;
        END IF;

        IF NOT reconciliation_run_has_outbox_evidence(run_row.id) THEN
          RAISE EXCEPTION 'reconciliation run requires outbox evidence';
        END IF;

        IF NOT EXISTS (
          SELECT 1
          FROM reconciliation_rows
          WHERE reconciliation_run_id = run_row.id
        ) THEN
          RAISE EXCEPTION 'reconciliation run requires row evidence';
        END IF;

        IF run_row.status = 'matched' AND EXISTS (
          SELECT 1
          FROM reconciliation_rows
          WHERE reconciliation_run_id = run_row.id
            AND status <> 'matched'
        ) THEN
          RAISE EXCEPTION 'matched reconciliation run cannot contain discrepant rows';
        END IF;

        IF run_row.status = 'discrepant' AND NOT EXISTS (
          SELECT 1
          FROM reconciliation_rows
          WHERE reconciliation_run_id = run_row.id
            AND status <> 'matched'
        ) THEN
          RAISE EXCEPTION 'discrepant reconciliation run requires discrepant row evidence';
        END IF;

        IF EXISTS (
          SELECT 1
          FROM reconciliation_rows row
          LEFT JOIN journal_entries journal ON journal.id = row.journal_entry_id
          WHERE row.reconciliation_run_id = run_row.id
            AND (
              row.organization_id <> run_row.organization_id
              OR (journal.id IS NOT NULL AND journal.organization_id <> row.organization_id)
            )
        ) THEN
          RAISE EXCEPTION 'reconciliation rows must match run and journal organization';
        END IF;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_reconciliation_run_evidence_after_run_write()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        PERFORM assert_reconciliation_run_evidence(NEW.id);
        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION assert_reconciliation_run_evidence_after_row_write()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        PERFORM assert_reconciliation_run_evidence(COALESCE(NEW.reconciliation_run_id, OLD.reconciliation_run_id));
        RETURN COALESCE(NEW, OLD);
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_reconciliation_run_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF reconciliation_run_has_outbox_evidence(OLD.id) THEN
            RAISE EXCEPTION 'reconciliation runs with outbox evidence are immutable';
          END IF;
          RETURN OLD;
        END IF;

        IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
          OR OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.provider IS DISTINCT FROM NEW.provider
          OR OLD.statement_date IS DISTINCT FROM NEW.statement_date
          OR OLD.provider_balance_cents IS DISTINCT FROM NEW.provider_balance_cents
          OR OLD.ledger_balance_cents IS DISTINCT FROM NEW.ledger_balance_cents
          OR OLD.discrepancy_cents IS DISTINCT FROM NEW.discrepancy_cents
          OR OLD.correlation_id IS DISTINCT FROM NEW.correlation_id
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'reconciliation run identity and balances are immutable';
        END IF;

        IF reconciliation_run_has_outbox_evidence(OLD.id) THEN
          RAISE EXCEPTION 'reconciliation runs with outbox evidence are immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION prevent_reconciliation_row_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        run_id_to_check bigint;
      BEGIN
        run_id_to_check := COALESCE(NEW.reconciliation_run_id, OLD.reconciliation_run_id);

        IF reconciliation_run_has_outbox_evidence(run_id_to_check) THEN
          RAISE EXCEPTION 'reconciliation rows with outbox evidence are immutable';
        END IF;

        RETURN COALESCE(NEW, OLD);
      END;
      $$;

      DROP TRIGGER IF EXISTS reconciliation_runs_prevent_evidence_mutation ON reconciliation_runs;
      CREATE TRIGGER reconciliation_runs_prevent_evidence_mutation
      BEFORE UPDATE OR DELETE ON reconciliation_runs
      FOR EACH ROW EXECUTE FUNCTION prevent_reconciliation_run_evidence_mutation();

      DROP TRIGGER IF EXISTS reconciliation_rows_prevent_evidence_mutation ON reconciliation_rows;
      CREATE TRIGGER reconciliation_rows_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON reconciliation_rows
      FOR EACH ROW EXECUTE FUNCTION prevent_reconciliation_row_evidence_mutation();

      DROP TRIGGER IF EXISTS reconciliation_runs_evidence_after_write ON reconciliation_runs;
      CREATE CONSTRAINT TRIGGER reconciliation_runs_evidence_after_write
      AFTER INSERT OR UPDATE ON reconciliation_runs
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_reconciliation_run_evidence_after_run_write();

      DROP TRIGGER IF EXISTS reconciliation_rows_evidence_after_write ON reconciliation_rows;
      CREATE CONSTRAINT TRIGGER reconciliation_rows_evidence_after_write
      AFTER INSERT OR UPDATE OR DELETE ON reconciliation_rows
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_reconciliation_run_evidence_after_row_write();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS reconciliation_rows_evidence_after_write ON reconciliation_rows;
      DROP TRIGGER IF EXISTS reconciliation_runs_evidence_after_write ON reconciliation_runs;
      DROP TRIGGER IF EXISTS reconciliation_rows_prevent_evidence_mutation ON reconciliation_rows;
      DROP TRIGGER IF EXISTS reconciliation_runs_prevent_evidence_mutation ON reconciliation_runs;
      DROP FUNCTION IF EXISTS prevent_reconciliation_row_evidence_mutation();
      DROP FUNCTION IF EXISTS prevent_reconciliation_run_evidence_mutation();
      DROP FUNCTION IF EXISTS assert_reconciliation_run_evidence_after_row_write();
      DROP FUNCTION IF EXISTS assert_reconciliation_run_evidence_after_run_write();
      DROP FUNCTION IF EXISTS assert_reconciliation_run_evidence(bigint);
      DROP FUNCTION IF EXISTS reconciliation_run_has_outbox_evidence(bigint);
    SQL

    remove_check_constraint :reconciliation_rows, name: "reconciliation_rows_amount_status_check"
    remove_check_constraint :reconciliation_runs, name: "reconciliation_runs_discrepancy_check"
    remove_check_constraint :reconciliation_runs, name: "reconciliation_runs_status_check"
    remove_check_constraint :reconciliation_runs, name: "reconciliation_runs_provider_present_check"
  end

  private

  def backfill_legacy_reconciliation_rows
    execute <<~SQL
      INSERT INTO reconciliation_rows (
        organization_id,
        reconciliation_run_id,
        row_type,
        status,
        external_id,
        occurred_on,
        provider_amount_cents,
        ledger_amount_cents,
        difference_cents,
        currency,
        metadata,
        created_at,
        updated_at
      )
      SELECT
        rr.organization_id,
        rr.id,
        'cash_balance',
        CASE WHEN rr.discrepancy_cents = 0 THEN 'matched' ELSE 'discrepant' END,
        'cash_balance:' || rr.provider || ':' || rr.statement_date::text,
        rr.statement_date,
        rr.provider_balance_cents,
        rr.ledger_balance_cents,
        rr.discrepancy_cents,
        COALESCE(rr.metadata->>'currency', 'BRL'),
        jsonb_build_object(
          'provider', rr.provider,
          'statement_date', rr.statement_date::text,
          'backfilled_legacy_row', true
        ),
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM reconciliation_runs rr
      WHERE NOT EXISTS (
        SELECT 1
        FROM reconciliation_rows row
        WHERE row.reconciliation_run_id = rr.id
      );
    SQL
  end

  def reconciliation_row_amount_status_check
    <<~SQL.squish
      (
        status = 'matched'
        AND difference_cents = 0
      )
      OR (
        status = 'discrepant'
        AND difference_cents <> 0
      )
      OR (
        status = 'missing_in_ledger'
        AND ledger_amount_cents = 0
        AND provider_amount_cents <> 0
      )
      OR (
        status = 'missing_in_provider'
        AND provider_amount_cents = 0
        AND ledger_amount_cents <> 0
      )
    SQL
  end
end
