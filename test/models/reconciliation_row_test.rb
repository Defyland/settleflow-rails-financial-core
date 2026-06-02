require "test_helper"

class ReconciliationRowTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @run = Reconciliation::Run.call(
      organization: @organization,
      provider: "bank-sandbox",
      statement_date: Date.current,
      provider_balance_cents: 0
    )
  end

  test "database prevents row insertion after reconciliation outbox evidence" do
    row = @run.reconciliation_rows.find_by!(row_type: "cash_balance")

    assert_raises(ActiveRecord::StatementInvalid) do
      ReconciliationRow.insert!({
        organization_id: @organization.id,
        reconciliation_run_id: @run.id,
        row_type: row.row_type,
        status: row.status,
        external_id: row.external_id,
        occurred_on: row.occurred_on,
        provider_amount_cents: row.provider_amount_cents,
        ledger_amount_cents: row.ledger_amount_cents,
        difference_cents: row.difference_cents,
        currency: row.currency,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects row type and status combinations that bypass model validation" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      ReconciliationRow.transaction(requires_new: true) do
        run_id = ReconciliationRun.insert!({
          organization_id: @organization.id,
          provider: "constraint-test-bank",
          statement_date: Date.current.next_day,
          provider_balance_cents: 0,
          ledger_balance_cents: 0,
          discrepancy_cents: 0,
          status: "matched",
          created_at: Time.current,
          updated_at: Time.current
        }).first.fetch("id")

        ReconciliationRow.insert_all!([
          {
            organization_id: @organization.id,
            reconciliation_run_id: run_id,
            row_type: "ledger_statement_entry",
            status: "matched",
            external_id: "invalid-ledger-match",
            occurred_on: Date.current,
            provider_amount_cents: 0,
            ledger_amount_cents: 0,
            difference_cents: 0,
            currency: "BRL",
            metadata: {},
            created_at: Time.current,
            updated_at: Time.current
          }
        ])
      end
    end

    assert_match(/reconciliation_rows_type_status_check/, error.message)
  end
end
