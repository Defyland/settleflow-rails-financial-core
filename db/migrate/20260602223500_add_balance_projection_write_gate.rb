class AddBalanceProjectionWriteGate < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION assert_balance_projection_amount_write_context()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        write_context text;
      BEGIN
        write_context := current_setting('settleflow.balance_projection_write_context', true);

        IF COALESCE(NULLIF(btrim(write_context), ''), 'none') NOT IN ('ledger_journal_poster', 'balance_projection_rebuilder') THEN
          RAISE EXCEPTION 'balance projection amount updates require ledger or rebuild write context';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS balance_projections_amount_write_gate_before_update ON balance_projections;
      CREATE TRIGGER balance_projections_amount_write_gate_before_update
      BEFORE UPDATE OF available_cents, pending_cents, blocked_cents ON balance_projections
      FOR EACH ROW
      WHEN (
        OLD.available_cents IS DISTINCT FROM NEW.available_cents
        OR OLD.pending_cents IS DISTINCT FROM NEW.pending_cents
        OR OLD.blocked_cents IS DISTINCT FROM NEW.blocked_cents
      )
      EXECUTE FUNCTION assert_balance_projection_amount_write_context();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS balance_projections_amount_write_gate_before_update ON balance_projections;
      DROP FUNCTION IF EXISTS assert_balance_projection_amount_write_context();
    SQL
  end
end
