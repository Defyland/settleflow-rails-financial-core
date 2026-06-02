class AddBalanceEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM balance_projections bp
          LEFT JOIN wallets w ON w.id = bp.wallet_id
          WHERE w.id IS NULL
             OR w.organization_id <> bp.organization_id
             OR w.currency <> bp.currency
        ) THEN
          RAISE EXCEPTION 'existing balance_projections violate wallet evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1
          FROM balance_snapshots bs
          LEFT JOIN wallets w ON w.id = bs.wallet_id
          WHERE w.id IS NULL
             OR w.organization_id <> bs.organization_id
             OR w.currency <> bs.currency
             OR bs.difference_cents <> bs.available_cents - bs.ledger_available_cents
             OR btrim(bs.source) = ''
        ) THEN
          RAISE EXCEPTION 'existing balance_snapshots violate evidence guards';
        END IF;
      END
      $$;
    SQL

    add_check_constraint :balance_snapshots,
      "difference_cents = available_cents - ledger_available_cents",
      name: "balance_snapshots_difference_matches_projection_check",
      validate: false
    add_check_constraint :balance_snapshots,
      "btrim(source) <> ''",
      name: "balance_snapshots_source_present_check",
      validate: false
    validate_check_constraint :balance_snapshots, name: "balance_snapshots_difference_matches_projection_check"
    validate_check_constraint :balance_snapshots, name: "balance_snapshots_source_present_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION assert_balance_projection_wallet_evidence()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        wallet_row wallets%ROWTYPE;
      BEGIN
        SELECT * INTO wallet_row
        FROM wallets
        WHERE id = NEW.wallet_id;

        IF wallet_row.id IS NULL THEN
          RAISE EXCEPTION 'balance projection must reference an existing wallet';
        END IF;

        IF wallet_row.organization_id <> NEW.organization_id THEN
          RAISE EXCEPTION 'balance projection organization must match wallet organization';
        END IF;

        IF wallet_row.currency <> NEW.currency THEN
          RAISE EXCEPTION 'balance projection currency must match wallet currency';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS balance_projections_wallet_evidence_before_write ON balance_projections;
      CREATE TRIGGER balance_projections_wallet_evidence_before_write
      BEFORE INSERT OR UPDATE OF organization_id, wallet_id, currency ON balance_projections
      FOR EACH ROW EXECUTE FUNCTION assert_balance_projection_wallet_evidence();

      CREATE OR REPLACE FUNCTION prevent_balance_snapshot_evidence_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        wallet_row wallets%ROWTYPE;
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'balance snapshots are append-only evidence';
        END IF;

        IF TG_OP = 'UPDATE' THEN
          RAISE EXCEPTION 'balance snapshots are immutable evidence';
        END IF;

        SELECT * INTO wallet_row
        FROM wallets
        WHERE id = NEW.wallet_id;

        IF wallet_row.id IS NULL THEN
          RAISE EXCEPTION 'balance snapshot must reference an existing wallet';
        END IF;

        IF wallet_row.organization_id <> NEW.organization_id THEN
          RAISE EXCEPTION 'balance snapshot organization must match wallet organization';
        END IF;

        IF wallet_row.currency <> NEW.currency THEN
          RAISE EXCEPTION 'balance snapshot currency must match wallet currency';
        END IF;

        IF NEW.difference_cents <> NEW.available_cents - NEW.ledger_available_cents THEN
          RAISE EXCEPTION 'balance snapshot difference must match projection minus ledger';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS balance_snapshots_prevent_evidence_mutation ON balance_snapshots;
      CREATE TRIGGER balance_snapshots_prevent_evidence_mutation
      BEFORE INSERT OR UPDATE OR DELETE ON balance_snapshots
      FOR EACH ROW EXECUTE FUNCTION prevent_balance_snapshot_evidence_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS balance_snapshots_prevent_evidence_mutation ON balance_snapshots;
      DROP FUNCTION IF EXISTS prevent_balance_snapshot_evidence_mutation();
      DROP TRIGGER IF EXISTS balance_projections_wallet_evidence_before_write ON balance_projections;
      DROP FUNCTION IF EXISTS assert_balance_projection_wallet_evidence();
    SQL

    remove_check_constraint :balance_snapshots, name: "balance_snapshots_source_present_check"
    remove_check_constraint :balance_snapshots, name: "balance_snapshots_difference_matches_projection_check"
  end
end
