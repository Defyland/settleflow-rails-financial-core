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

  test "database rejects direct ledger mutation and deletion bypassing models" do
    journal = post_test_journal
    line = journal.ledger_lines.first

    assert_database_constraint_violation { journal.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { line.update_columns(amount_cents: line.amount_cents + 1) }
    assert_database_constraint_violation { LedgerLine.where(id: line.id).delete_all }
    assert_database_constraint_violation { JournalEntry.where(id: journal.id).delete_all }
  end

  test "database rejects ledger lines whose account belongs to another organization" do
    journal = post_test_journal
    other_organization = create_organization
    other_wallet = create_wallet(organization: other_organization)

    assert_database_constraint_violation do
      LedgerLine.insert!({
        organization_id: @organization.id,
        journal_entry_id: journal.id,
        ledger_account_id: other_wallet.liability_account.id,
        direction: "credit",
        amount_cents: 1,
        currency: "BRL",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  private

  def post_test_journal
    destination_wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-funding-#{SecureRandom.hex(4)}",
      amount_cents: 10
    )
    transfer = @organization.transfers.create!(
      source_wallet: @wallet,
      destination_wallet:,
      external_id: "db-invariant-transfer-#{SecureRandom.hex(4)}",
      amount_cents: 1,
      currency: "BRL",
      idempotency_key: "db-invariant-transfer-#{SecureRandom.hex(4)}"
    )

    Ledger::JournalPoster.call(
      organization: @organization,
      event_type: "db_invariant.test_journal",
      reference: transfer,
      idempotency_key: "db-invariant-journal-#{SecureRandom.hex(4)}",
      lines: [
        { account: @wallet.liability_account, direction: "debit", amount_cents: 1, currency: "BRL" },
        { account: destination_wallet.liability_account, direction: "credit", amount_cents: 1, currency: "BRL" }
      ]
    )
  end

  def assert_database_constraint_violation
    connection = ActiveRecord::Base.connection
    connection.execute("SAVEPOINT database_invariant_test")

    assert_raises(ActiveRecord::StatementInvalid) { yield }
  ensure
    connection.execute("ROLLBACK TO SAVEPOINT database_invariant_test")
    connection.execute("RELEASE SAVEPOINT database_invariant_test")
  end
end
