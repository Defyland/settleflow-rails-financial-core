class AddWalletCommandEvidenceGuards < ActiveRecord::Migration[8.1]
  def up
    add_column :fundings, :failure_code, :string
    add_check_constraint :fundings,
      "status IN ('posted', 'failed')",
      name: "fundings_status_check",
      validate: false
    validate_check_constraint :fundings, name: "fundings_status_check"
    add_check_constraint :transfers,
      "status IN ('posted', 'failed')",
      name: "transfers_status_check",
      validate: false
    validate_check_constraint :transfers, name: "transfers_status_check"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION assert_funding_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        funding_row fundings%ROWTYPE;
      BEGIN
        SELECT * INTO funding_row FROM fundings WHERE id = NEW.id;

        IF NOT EXISTS (
          SELECT 1
          FROM wallets
          WHERE wallets.id = funding_row.wallet_id
            AND wallets.organization_id = funding_row.organization_id
            AND wallets.currency = funding_row.currency
        ) THEN
          RAISE EXCEPTION 'funding wallet must match organization and currency';
        END IF;

        IF funding_row.status = 'posted' AND funding_row.journal_entry_id IS NULL THEN
          RAISE EXCEPTION 'posted funding requires journal evidence';
        END IF;

        IF funding_row.status = 'failed'
          AND (funding_row.failure_code IS NULL OR funding_row.journal_entry_id IS NOT NULL) THEN
          RAISE EXCEPTION 'failed funding requires failure evidence without journal';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION assert_transfer_state_evidence()
      RETURNS trigger AS $$
      DECLARE
        transfer_row transfers%ROWTYPE;
      BEGIN
        SELECT * INTO transfer_row FROM transfers WHERE id = NEW.id;

        IF NOT EXISTS (
          SELECT 1
          FROM wallets source_wallets
          JOIN wallets destination_wallets ON destination_wallets.id = transfer_row.destination_wallet_id
          WHERE source_wallets.id = transfer_row.source_wallet_id
            AND source_wallets.id <> destination_wallets.id
            AND source_wallets.organization_id = transfer_row.organization_id
            AND destination_wallets.organization_id = transfer_row.organization_id
            AND source_wallets.currency = transfer_row.currency
            AND destination_wallets.currency = transfer_row.currency
        ) THEN
          RAISE EXCEPTION 'transfer wallets must match organization, currency, and be different';
        END IF;

        IF transfer_row.status = 'posted' AND transfer_row.journal_entry_id IS NULL THEN
          RAISE EXCEPTION 'posted transfer requires journal evidence';
        END IF;

        IF transfer_row.status = 'failed'
          AND (transfer_row.failure_code IS NULL OR transfer_row.journal_entry_id IS NOT NULL) THEN
          RAISE EXCEPTION 'failed transfer requires failure evidence without journal';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION assert_split_payment_state_evidence(split_payment_id_to_check bigint)
      RETURNS void AS $$
      DECLARE
        split_payment_row split_payments%ROWTYPE;
        split_entry_count integer;
        split_entry_total bigint;
        mismatched_entry_count integer;
      BEGIN
        SELECT * INTO split_payment_row FROM split_payments WHERE id = split_payment_id_to_check;
        IF NOT FOUND THEN
          RETURN;
        END IF;

        IF NOT EXISTS (
          SELECT 1
          FROM wallets
          WHERE wallets.id = split_payment_row.source_wallet_id
            AND wallets.organization_id = split_payment_row.organization_id
            AND wallets.currency = split_payment_row.currency
        ) THEN
          RAISE EXCEPTION 'split source wallet must match organization and currency';
        END IF;

        SELECT COUNT(*), COALESCE(SUM(amount_cents), 0)
        INTO split_entry_count, split_entry_total
        FROM split_entries
        WHERE split_payment_id = split_payment_row.id;

        SELECT COUNT(*)
        INTO mismatched_entry_count
        FROM split_entries
        JOIN wallets ON wallets.id = split_entries.destination_wallet_id
        WHERE split_entries.split_payment_id = split_payment_row.id
          AND (
            split_entries.organization_id <> split_payment_row.organization_id
            OR split_entries.currency <> split_payment_row.currency
            OR wallets.organization_id <> split_payment_row.organization_id
            OR wallets.currency <> split_payment_row.currency
            OR wallets.id = split_payment_row.source_wallet_id
          );

        IF split_payment_row.status = 'posted'
          AND (
            split_payment_row.journal_entry_id IS NULL
            OR split_entry_count = 0
            OR split_entry_total <> split_payment_row.total_amount_cents
            OR mismatched_entry_count > 0
          ) THEN
          RAISE EXCEPTION 'posted split requires journal evidence and matching destination entries';
        END IF;

        IF split_payment_row.status = 'failed'
          AND (split_payment_row.failure_code IS NULL OR split_payment_row.journal_entry_id IS NOT NULL) THEN
          RAISE EXCEPTION 'failed split requires failure evidence without journal';
        END IF;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION assert_split_payment_state_evidence_trigger()
      RETURNS trigger AS $$
      BEGIN
        PERFORM assert_split_payment_state_evidence(NEW.id);
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION assert_split_entry_state_evidence_trigger()
      RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          PERFORM assert_split_payment_state_evidence(OLD.split_payment_id);
          RETURN OLD;
        END IF;

        PERFORM assert_split_payment_state_evidence(NEW.split_payment_id);
        IF TG_OP = 'UPDATE' AND OLD.split_payment_id <> NEW.split_payment_id THEN
          PERFORM assert_split_payment_state_evidence(OLD.split_payment_id);
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM fundings
          JOIN wallets ON wallets.id = fundings.wallet_id
          WHERE (fundings.status = 'posted' AND fundings.journal_entry_id IS NULL)
             OR (fundings.status = 'failed' AND (fundings.failure_code IS NULL OR fundings.journal_entry_id IS NOT NULL))
             OR wallets.organization_id <> fundings.organization_id
             OR wallets.currency <> fundings.currency
        ) THEN
          RAISE EXCEPTION 'existing fundings violate state evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1
          FROM transfers
          JOIN wallets source_wallets ON source_wallets.id = transfers.source_wallet_id
          JOIN wallets destination_wallets ON destination_wallets.id = transfers.destination_wallet_id
          WHERE (transfers.status = 'posted' AND transfers.journal_entry_id IS NULL)
             OR (transfers.status = 'failed' AND (transfers.failure_code IS NULL OR transfers.journal_entry_id IS NOT NULL))
             OR source_wallets.id = destination_wallets.id
             OR source_wallets.organization_id <> transfers.organization_id
             OR destination_wallets.organization_id <> transfers.organization_id
             OR source_wallets.currency <> transfers.currency
             OR destination_wallets.currency <> transfers.currency
        ) THEN
          RAISE EXCEPTION 'existing transfers violate state evidence guards';
        END IF;

        IF EXISTS (
          SELECT 1
          FROM split_payments
          JOIN wallets source_wallets ON source_wallets.id = split_payments.source_wallet_id
          WHERE split_payments.status = 'posted'
            AND (
              split_payments.journal_entry_id IS NULL
              OR COALESCE((SELECT SUM(amount_cents) FROM split_entries WHERE split_payment_id = split_payments.id), 0) <> split_payments.total_amount_cents
              OR NOT EXISTS (SELECT 1 FROM split_entries WHERE split_payment_id = split_payments.id)
              OR source_wallets.organization_id <> split_payments.organization_id
              OR source_wallets.currency <> split_payments.currency
              OR EXISTS (
                SELECT 1
                FROM split_entries
                JOIN wallets destination_wallets ON destination_wallets.id = split_entries.destination_wallet_id
                WHERE split_entries.split_payment_id = split_payments.id
                  AND (
                    split_entries.organization_id <> split_payments.organization_id
                    OR split_entries.currency <> split_payments.currency
                    OR destination_wallets.organization_id <> split_payments.organization_id
                    OR destination_wallets.currency <> split_payments.currency
                    OR destination_wallets.id = split_payments.source_wallet_id
                  )
              )
            )
        ) THEN
          RAISE EXCEPTION 'existing split payments violate state evidence guards';
        END IF;
      END;
      $$;

      DROP TRIGGER IF EXISTS fundings_state_evidence_after_write ON fundings;
      CREATE CONSTRAINT TRIGGER fundings_state_evidence_after_write
      AFTER INSERT OR UPDATE ON fundings
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_funding_state_evidence();

      DROP TRIGGER IF EXISTS transfers_state_evidence_after_write ON transfers;
      CREATE CONSTRAINT TRIGGER transfers_state_evidence_after_write
      AFTER INSERT OR UPDATE ON transfers
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_transfer_state_evidence();

      DROP TRIGGER IF EXISTS split_payments_state_evidence_after_write ON split_payments;
      CREATE CONSTRAINT TRIGGER split_payments_state_evidence_after_write
      AFTER INSERT OR UPDATE ON split_payments
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_split_payment_state_evidence_trigger();

      DROP TRIGGER IF EXISTS split_entries_state_evidence_after_write ON split_entries;
      CREATE CONSTRAINT TRIGGER split_entries_state_evidence_after_write
      AFTER INSERT OR UPDATE OR DELETE ON split_entries
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_split_entry_state_evidence_trigger();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS split_entries_state_evidence_after_write ON split_entries;
      DROP TRIGGER IF EXISTS split_payments_state_evidence_after_write ON split_payments;
      DROP TRIGGER IF EXISTS transfers_state_evidence_after_write ON transfers;
      DROP TRIGGER IF EXISTS fundings_state_evidence_after_write ON fundings;
      DROP FUNCTION IF EXISTS assert_split_entry_state_evidence_trigger();
      DROP FUNCTION IF EXISTS assert_split_payment_state_evidence_trigger();
      DROP FUNCTION IF EXISTS assert_split_payment_state_evidence(bigint);
      DROP FUNCTION IF EXISTS assert_transfer_state_evidence();
      DROP FUNCTION IF EXISTS assert_funding_state_evidence();
    SQL
    remove_check_constraint :transfers, name: "transfers_status_check"
    remove_check_constraint :fundings, name: "fundings_status_check"
    remove_column :fundings, :failure_code
  end
end
