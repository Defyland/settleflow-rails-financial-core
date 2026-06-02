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
    assert_equal "BRL", run.metadata.fetch("currency")
    assert_equal 12_345, run.metadata.fetch("platform_cash_cents")
    assert_equal 12_345, run.metadata.fetch("wallet_liability_cents")
    assert_equal 12_345, run.metadata.fetch("projection_available_cents")
    assert_equal 0, run.metadata.fetch("projection_difference_cents")
    assert_equal 0, run.metadata.fetch("pix_clearing_cents")
    assert_equal 0, run.metadata.fetch("payout_clearing_cents")
    assert_equal({ "discrepant" => 1, "matched" => 1 }, run.metadata.fetch("row_status_counts"))
    assert_equal %w[cash_balance projection_balance], run.reconciliation_rows.order(:id).map(&:row_type)
  end

  test "marks projection divergence as discrepant even when provider cash matches" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(
      organization:,
      wallet:,
      external_id: "recon-projection-funding",
      amount_cents: 12_345
    )
    force_balance_projection_drift!(wallet.balance_projection, available_cents: 12_000)

    run = Reconciliation::Run.call(
      organization:,
      provider: "bank-sandbox",
      statement_date: Date.new(2026, 5, 30),
      provider_balance_cents: 12_345
    )

    assert run.discrepant?
    assert_equal 0, run.discrepancy_cents
    assert_equal(-345, run.metadata.fetch("projection_difference_cents"))
    assert_equal "discrepant", run.reconciliation_rows.find_by!(row_type: "projection_balance").status
  end

  test "creates itemized reconciliation rows for provider statement entries" do
    organization = create_organization
    matched_wallet = create_wallet(organization:)
    missing_provider_wallet = create_wallet(organization:)
    fund_wallet(
      organization:,
      wallet: matched_wallet,
      external_id: "recon-provider-matched",
      amount_cents: 1_000
    )
    fund_wallet(
      organization:,
      wallet: missing_provider_wallet,
      external_id: "recon-missing-provider",
      amount_cents: 300
    )

    run = Reconciliation::Run.call(
      organization:,
      provider: "bank-sandbox",
      statement_date: Date.current,
      provider_balance_cents: 1_300,
      statement_entries: [
        { external_id: "recon-provider-matched", amount_cents: 1_000, occurred_on: Date.current.iso8601 },
        { external_id: "recon-missing-ledger", amount_cents: 500, occurred_on: Date.current.iso8601 }
      ]
    )

    assert run.discrepant?
    assert_equal 5, run.reconciliation_rows.count
    assert_equal(
      { "matched" => 3, "missing_in_ledger" => 1, "missing_in_provider" => 1 },
      run.metadata.fetch("row_status_counts")
    )

    matched_row = run.reconciliation_rows.find_by!(external_id: "recon-provider-matched")
    assert matched_row.matched?
    assert_equal 1_000, matched_row.provider_amount_cents
    assert_equal 1_000, matched_row.ledger_amount_cents
    assert matched_row.journal_entry.present?

    missing_ledger_row = run.reconciliation_rows.find_by!(external_id: "recon-missing-ledger")
    assert missing_ledger_row.missing_in_ledger?
    assert_equal 500, missing_ledger_row.difference_cents

    missing_provider_row = run.reconciliation_rows.find_by!(external_id: "recon-missing-provider")
    assert missing_provider_row.missing_in_provider?
    assert_equal(-300, missing_provider_row.difference_cents)
  end
end
