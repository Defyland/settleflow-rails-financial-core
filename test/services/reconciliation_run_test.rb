require "test_helper"

class ReconciliationRunTest < ActiveSupport::TestCase
  test "compares provider balance with the platform cash ledger" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(
      organization:,
      wallet:,
      external_id: "recon-funding",
      amount_cents: 12_345
    )

    run = Reconciliation::Run.call(
      organization:,
      provider: "bank-sandbox",
      statement_date: Date.new(2026, 5, 29),
      provider_balance_cents: 12_300
    )

    assert run.discrepant?
    assert_equal 12_345, run.ledger_balance_cents
    assert_equal(-45, run.discrepancy_cents)
  end
end
