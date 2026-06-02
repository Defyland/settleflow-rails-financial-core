require "test_helper"

class DatabaseFinancialInvariantsTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
  end

  test "database rejects negative balance projections" do
    assert_raises(ActiveRecord::StatementInvalid) do
      @wallet.balance_projection.update_columns(available_cents: -1)
    end
  end

  test "database rejects journal entries without command identity" do
    assert_raises(ActiveRecord::StatementInvalid) do
      JournalEntry.insert!({
        organization_id: @organization.id,
        event_type: "raw.missing_idempotency",
        occurred_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects direct unbalanced journal inserts" do
    destination_wallet = create_wallet(organization: @organization)
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction do
        journal_id = JournalEntry.insert!({
          organization_id: @organization.id,
          event_type: "raw.unbalanced",
          idempotency_key: "raw-unbalanced",
          occurred_at: Time.current,
          created_at: Time.current,
          updated_at: Time.current
        }).first["id"]

        LedgerLine.insert_all!([
          {
            organization_id: @organization.id,
            journal_entry_id: journal_id,
            ledger_account_id: @wallet.liability_account.id,
            direction: "debit",
            amount_cents: 100,
            currency: "BRL",
            created_at: Time.current,
            updated_at: Time.current
          },
          {
            organization_id: @organization.id,
            journal_entry_id: journal_id,
            ledger_account_id: destination_wallet.liability_account.id,
            direction: "credit",
            amount_cents: 99,
            currency: "BRL",
            created_at: Time.current,
            updated_at: Time.current
          }
        ])
        ActiveRecord::Base.connection.execute(
          "SET CONSTRAINTS journal_entry_balanced_after_journal_insert, journal_entry_balanced_after_line_insert IMMEDIATE"
        )
      end
    end
  end
end
