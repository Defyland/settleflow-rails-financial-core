class AddFinancialCoreDatabaseGuards < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :balance_projections, "available_cents >= 0", name: "balance_projections_available_non_negative_check", validate: false
    add_check_constraint :balance_projections, "pending_cents >= 0", name: "balance_projections_pending_non_negative_check", validate: false
    add_check_constraint :balance_projections, "blocked_cents >= 0", name: "balance_projections_blocked_non_negative_check", validate: false
    validate_check_constraint :balance_projections, name: "balance_projections_available_non_negative_check"
    validate_check_constraint :balance_projections, name: "balance_projections_pending_non_negative_check"
    validate_check_constraint :balance_projections, name: "balance_projections_blocked_non_negative_check"

    execute "UPDATE journal_entries SET idempotency_key = 'legacy-journal-entry:' || id WHERE idempotency_key IS NULL"
    add_check_constraint :journal_entries, "idempotency_key IS NOT NULL", name: "journal_entries_idempotency_key_required_check", validate: false
    validate_check_constraint :journal_entries, name: "journal_entries_idempotency_key_required_check"
    change_column_null :journal_entries, :idempotency_key, false

    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_ledger_record_mutation()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'ledger records are append-only';
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS prevent_journal_entry_mutation ON journal_entries;
      CREATE TRIGGER prevent_journal_entry_mutation
      BEFORE UPDATE OR DELETE ON journal_entries
      FOR EACH ROW EXECUTE FUNCTION prevent_ledger_record_mutation();

      DROP TRIGGER IF EXISTS prevent_ledger_line_mutation ON ledger_lines;
      CREATE TRIGGER prevent_ledger_line_mutation
      BEFORE UPDATE OR DELETE ON ledger_lines
      FOR EACH ROW EXECUTE FUNCTION prevent_ledger_record_mutation();

      CREATE OR REPLACE FUNCTION enforce_ledger_line_account_consistency()
      RETURNS trigger AS $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM ledger_accounts
          WHERE ledger_accounts.id = NEW.ledger_account_id
            AND ledger_accounts.organization_id = NEW.organization_id
            AND ledger_accounts.currency = NEW.currency
        ) THEN
          RAISE EXCEPTION 'ledger line account must match organization and currency';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS enforce_ledger_line_account_consistency ON ledger_lines;
      CREATE TRIGGER enforce_ledger_line_account_consistency
      BEFORE INSERT ON ledger_lines
      FOR EACH ROW EXECUTE FUNCTION enforce_ledger_line_account_consistency();

      CREATE OR REPLACE FUNCTION assert_journal_entry_balanced(journal_entry_id_to_check bigint)
      RETURNS void AS $$
      DECLARE
        line_count integer;
        imbalance_count integer;
      BEGIN
        SELECT COUNT(*) INTO line_count
        FROM ledger_lines
        WHERE journal_entry_id = journal_entry_id_to_check;

        IF line_count < 2 THEN
          RAISE EXCEPTION 'journal entry must have at least two ledger lines';
        END IF;

        SELECT COUNT(*) INTO imbalance_count
        FROM (
          SELECT currency
          FROM ledger_lines
          WHERE journal_entry_id = journal_entry_id_to_check
          GROUP BY currency
          HAVING
            SUM(CASE WHEN direction = 'debit' THEN amount_cents ELSE 0 END) <>
            SUM(CASE WHEN direction = 'credit' THEN amount_cents ELSE 0 END)
        ) imbalances;

        IF imbalance_count > 0 THEN
          RAISE EXCEPTION 'journal entry is not balanced';
        END IF;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION assert_inserted_journal_entry_balanced()
      RETURNS trigger AS $$
      BEGIN
        PERFORM assert_journal_entry_balanced(NEW.id);
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      CREATE OR REPLACE FUNCTION assert_ledger_line_journal_entry_balanced()
      RETURNS trigger AS $$
      BEGIN
        PERFORM assert_journal_entry_balanced(NEW.journal_entry_id);
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      DO $$
      DECLARE
        journal_entry_record record;
      BEGIN
        FOR journal_entry_record IN SELECT id FROM journal_entries LOOP
          PERFORM assert_journal_entry_balanced(journal_entry_record.id);
        END LOOP;
      END;
      $$;

      DROP TRIGGER IF EXISTS journal_entry_balanced_after_journal_insert ON journal_entries;
      CREATE CONSTRAINT TRIGGER journal_entry_balanced_after_journal_insert
      AFTER INSERT ON journal_entries
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_inserted_journal_entry_balanced();

      DROP TRIGGER IF EXISTS journal_entry_balanced_after_line_insert ON ledger_lines;
      CREATE CONSTRAINT TRIGGER journal_entry_balanced_after_line_insert
      AFTER INSERT ON ledger_lines
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION assert_ledger_line_journal_entry_balanced();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS journal_entry_balanced_after_line_insert ON ledger_lines;
      DROP TRIGGER IF EXISTS journal_entry_balanced_after_journal_insert ON journal_entries;
      DROP TRIGGER IF EXISTS enforce_ledger_line_account_consistency ON ledger_lines;
      DROP TRIGGER IF EXISTS prevent_ledger_line_mutation ON ledger_lines;
      DROP TRIGGER IF EXISTS prevent_journal_entry_mutation ON journal_entries;
      DROP FUNCTION IF EXISTS assert_ledger_line_journal_entry_balanced();
      DROP FUNCTION IF EXISTS assert_inserted_journal_entry_balanced();
      DROP FUNCTION IF EXISTS assert_journal_entry_balanced(bigint);
      DROP FUNCTION IF EXISTS enforce_ledger_line_account_consistency();
      DROP FUNCTION IF EXISTS prevent_ledger_record_mutation();
    SQL

    change_column_null :journal_entries, :idempotency_key, true
    remove_check_constraint :journal_entries, name: "journal_entries_idempotency_key_required_check", if_exists: true
    remove_check_constraint :balance_projections, name: "balance_projections_blocked_non_negative_check"
    remove_check_constraint :balance_projections, name: "balance_projections_pending_non_negative_check"
    remove_check_constraint :balance_projections, name: "balance_projections_available_non_negative_check"
  end
end
