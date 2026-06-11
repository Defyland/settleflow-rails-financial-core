require "test_helper"

class FinancialBranchCoverageTest < ActiveSupport::TestCase
  test "rejects cross-organization wallet commands" do
    organization = create_organization
    other_wallet = create_wallet(organization: create_organization)
    wallet = create_wallet(organization:)

    assert_validation("Wallet belongs to another organization") do
      Fundings::Create.call(organization:, wallet: other_wallet, external_id: "funding-cross-org", amount_cents: 1_000, idempotency_key: "funding-cross-org")
    end

    assert_validation("Wallet belongs to another organization") do
      Payouts::Create.call(organization:, wallet: other_wallet, external_id: "payout-cross-org", amount_cents: 1_000, destination_reference: "bank-cross-org", idempotency_key: "payout-cross-org")
    end

    assert_validation("Wallet belongs to another organization") do
      PixPayments::Create.call(organization:, wallet: other_wallet, external_id: "pix-cross-org", pix_key: "cross@example.com", receiver_name: "Receiver", amount_cents: 1_000, idempotency_key: "pix-cross-org")
    end

    assert_validation("Currency mismatch") do
      Payouts::Create.call(organization:, wallet:, external_id: "payout-currency", amount_cents: 1_000, currency: "USD", destination_reference: "bank-currency", idempotency_key: "payout-currency")
    end
  end

  test "rejects invalid transfer boundaries" do
    organization = create_organization
    source = create_wallet(organization:)
    destination = create_wallet(organization:)
    other_wallet = create_wallet(organization: create_organization)

    assert_validation("Source wallet belongs to another organization") do
      Transfers::Create.call(organization:, source_wallet: other_wallet, destination_wallet: destination, external_id: "transfer-source-org", amount_cents: 1_000, idempotency_key: "transfer-source-org")
    end

    assert_validation("Destination wallet belongs to another organization") do
      Transfers::Create.call(organization:, source_wallet: source, destination_wallet: other_wallet, external_id: "transfer-destination-org", amount_cents: 1_000, idempotency_key: "transfer-destination-org")
    end

    assert_validation("Source and destination wallets must be different") do
      Transfers::Create.call(organization:, source_wallet: source, destination_wallet: source, external_id: "transfer-same-wallet", amount_cents: 1_000, idempotency_key: "transfer-same-wallet")
    end

    assert_validation("Currency mismatch") do
      Transfers::Create.call(organization:, source_wallet: source, destination_wallet: destination, external_id: "transfer-currency", amount_cents: 1_000, currency: "USD", idempotency_key: "transfer-currency")
    end
  end

  test "rejects invalid split entry boundaries" do
    organization = create_organization
    source = create_wallet(organization:)
    destination = create_wallet(organization:)
    other_wallet = create_wallet(organization: create_organization)

    assert_validation("Split requires at least one destination") do
      SplitPayments::Create.call(organization:, source_wallet: source, external_id: "split-empty", entries: [], idempotency_key: "split-empty")
    end

    assert_validation("Split amount must be positive") do
      SplitPayments::Create.call(organization:, source_wallet: source, external_id: "split-zero", entries: [ { destination_wallet: destination, amount_cents: 0 } ], idempotency_key: "split-zero")
    end

    assert_validation("Split destinations must be present") do
      SplitPayments::Create.call(organization:, source_wallet: source, external_id: "split-missing-destination", entries: [ { amount_cents: 1_000 } ], idempotency_key: "split-missing-destination")
    end

    assert_validation("Split destinations must be unique") do
      SplitPayments::Create.call(
        organization:,
        source_wallet: source,
        external_id: "split-duplicate",
        entries: [
          { destination_wallet: destination, amount_cents: 500 },
          { destination_wallet: destination, amount_cents: 500 }
        ],
        idempotency_key: "split-duplicate"
      )
    end

    assert_validation("Source wallet cannot receive its own split") do
      SplitPayments::Create.call(organization:, source_wallet: source, external_id: "split-self", entries: [ { destination_wallet: source, amount_cents: 1_000 } ], idempotency_key: "split-self")
    end

    assert_validation("Destination wallet belongs to another organization") do
      SplitPayments::Create.call(organization:, source_wallet: source, external_id: "split-destination-org", entries: [ { destination_wallet: other_wallet, amount_cents: 1_000 } ], idempotency_key: "split-destination-org")
    end

    assert_validation("Currency mismatch") do
      SplitPayments::Create.call(organization:, source_wallet: source, external_id: "split-currency", currency: "USD", entries: [ { destination_wallet: destination, amount_cents: 1_000 } ], idempotency_key: "split-currency")
    end
  end

  test "rejects pix settlement and payout state boundary errors" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "branch-payout-funding", amount_cents: 5_000)
    pix_payment = create_pix_payment(organization:, wallet:, external_id: "branch-pix-settle", amount_cents: 1_000)
    other_organization = create_organization
    other_wallet = create_wallet(organization: other_organization)
    fund_wallet(organization: other_organization, wallet: other_wallet, external_id: "other-payout-funding", amount_cents: 2_000)
    other_pix_payment = create_pix_payment(organization: other_organization, wallet: other_wallet, external_id: "branch-other-pix", amount_cents: 1_000)
    other_payout = Payouts::Create.call(organization: other_organization, wallet: other_wallet, external_id: "other-payout", amount_cents: 1_000, destination_reference: "other-bank", idempotency_key: "other-payout")
    payout = Payouts::Create.call(organization:, wallet:, external_id: "branch-payout", amount_cents: 1_000, settlement_delay_days: 2, destination_reference: "bank-branch", idempotency_key: "branch-payout")

    assert_validation("Pix payment belongs to another organization") do
      PixPayments::Settle.call(organization:, pix_payment: other_pix_payment)
    end

    assert_validation("Settlement delay must be non-negative") do
      Payouts::Create.call(organization:, wallet:, external_id: "payout-negative-delay", amount_cents: 1_000, settlement_delay_days: -1, destination_reference: "bank-negative", idempotency_key: "payout-negative-delay")
    end

    assert_validation("Payout belongs to another organization") do
      Payouts::Settle.call(organization:, payout: other_payout)
    end

    assert_validation("Payout settlement date has not arrived") do
      Payouts::Settle.call(organization:, payout:)
    end

    assert pix_payment.approved?
  end

  test "rejects invalid refund boundaries" do
    organization, wallet, pix_payment = settled_pix_payment("refund-branch")
    other_pix_payment = settled_pix_payment("refund-other").last
    unsettled = create_pix_payment(organization:, wallet:, external_id: "refund-unsettled", amount_cents: 1_000)

    assert_validation("Pix payment belongs to another organization") do
      Refunds::Create.call(organization:, pix_payment: other_pix_payment, external_id: "refund-cross-org", amount_cents: 500, reason: "customer_request", idempotency_key: "refund-cross-org")
    end

    assert_validation("Currency mismatch") do
      Refunds::Create.call(organization:, pix_payment:, external_id: "refund-currency", amount_cents: 500, reason: "customer_request", currency: "USD", idempotency_key: "refund-currency")
    end

    assert_validation("Only settled Pix payments can be refunded") do
      Refunds::Create.call(organization:, pix_payment: unsettled, external_id: "refund-unsettled", amount_cents: 500, reason: "customer_request", idempotency_key: "refund-unsettled")
    end
  end

  test "rejects invalid MED open and terminal boundaries" do
    organization, _wallet, pix_payment = settled_pix_payment("med-branch")
    other_organization, _other_wallet, other_pix_payment = settled_pix_payment("med-other")
    operator = create_operator("med-branch")
    med_case = MedCases::Open.call(organization:, pix_payment:, external_id: "med-branch", amount_cents: 500, reason: "fraud_report", idempotency_key: "med-branch")
    other_med_case = MedCases::Open.call(organization: other_organization, pix_payment: other_pix_payment, external_id: "med-other", amount_cents: 500, reason: "fraud_report", idempotency_key: "med-other")
    MedCases::Reject.call(organization:, med_case:, operator:, reason: "insufficient_evidence")
    rejected_case = MedCases::Reject.call(organization:, med_case:, operator: create_operator("med-branch-checker"), reason: "insufficient_evidence").subject

    assert_raises(Errors::IdempotencyKeyRequired) do
      MedCases::Open.call(organization:, pix_payment:, external_id: "med-missing-idem", amount_cents: 500, reason: "fraud_report")
    end

    assert_validation("Pix payment belongs to another organization") do
      MedCases::Open.call(organization:, pix_payment: other_pix_payment, external_id: "med-cross-org", amount_cents: 500, reason: "fraud_report", idempotency_key: "med-cross-org")
    end

    assert_validation("Currency mismatch") do
      MedCases::Open.call(organization:, pix_payment:, external_id: "med-currency", amount_cents: 500, reason: "fraud_report", currency: "USD", idempotency_key: "med-currency")
    end

    assert_validation("MED amount exceeds Pix amount") do
      MedCases::Open.call(organization:, pix_payment:, external_id: "med-too-large", amount_cents: pix_payment.amount_cents + 1, reason: "fraud_report", idempotency_key: "med-too-large")
    end

    assert_validation("MED case belongs to another organization") do
      MedCases::Accept.call(organization:, med_case: other_med_case, operator:)
    end

    assert_validation("MED case belongs to another organization") do
      MedCases::Reject.call(organization:, med_case: other_med_case, operator:, reason: "cross_org")
    end

    assert_validation("MED case must be opened before refund") do
      MedCases::Accept.call(organization:, med_case: rejected_case, operator:)
    end

    assert_validation("MED case must be opened before rejection") do
      MedCases::Reject.call(organization:, med_case: rejected_case, operator:, reason: "duplicate_reject")
    end
  end

  test "rejects invalid journal and reconciliation evidence" do
    organization = create_organization
    source = create_wallet(organization:)
    destination = create_wallet(organization:)
    transfer = organization.transfers.create!(source_wallet: source, destination_wallet: destination, external_id: "journal-branch", amount_cents: 1_000, currency: "BRL", idempotency_key: "journal-branch")

    assert_validation("Journal entry requires at least two lines") do
      Ledger::JournalPoster.call(organization:, event_type: "wallet.transfer.posted", reference: transfer, idempotency_key: "journal-one-line", lines: [ { account: source.liability_account, direction: "debit", amount_cents: 1_000, currency: "BRL" } ])
    end

    assert_validation("Ledger account belongs to another organization") do
      other_account = create_wallet(organization: create_organization).liability_account
      Ledger::JournalPoster.call(organization:, event_type: "wallet.transfer.posted", reference: transfer, idempotency_key: "journal-account-org", lines: [ { account: other_account, direction: "debit", amount_cents: 1_000, currency: "BRL" }, { account: destination.liability_account, direction: "credit", amount_cents: 1_000, currency: "BRL" } ])
    end

    assert_validation("Ledger account currency mismatch") do
      Ledger::JournalPoster.call(organization:, event_type: "wallet.transfer.posted", reference: transfer, idempotency_key: "journal-currency", lines: [ { account: source.liability_account, direction: "debit", amount_cents: 1_000, currency: "USD" }, { account: destination.liability_account, direction: "credit", amount_cents: 1_000, currency: "USD" } ])
    end

    assert_validation("Statement entry currency mismatch") do
      Reconciliation::Run.call(organization:, provider: "bank-branch", statement_date: Date.current, provider_balance_cents: 0, statement_entries: [ { external_id: "bad-currency", amount_cents: 100, currency: "USD" } ])
    end

    assert_validation("Statement entry external_id is required") do
      Reconciliation::Run.call(organization:, provider: "bank-branch-missing", statement_date: Date.current, provider_balance_cents: 0, statement_entries: [ { amount_cents: 100 } ])
    end

    assert_validation("Statement entry occurred_on must be ISO-8601") do
      Reconciliation::Run.call(organization:, provider: "bank-branch-date", statement_date: Date.current, provider_balance_cents: 0, statement_entries: [ { external_id: "bad-date", amount_cents: 100, occurred_on: "not-a-date" } ])
    end
  end

  private

  def assert_validation(message)
    error = assert_raises(Errors::ValidationError) { yield }
    assert_equal message, error.message
  end

  def settled_pix_payment(prefix)
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "#{prefix}-funding", amount_cents: 5_000)
    pix_payment = create_pix_payment(organization:, wallet:, external_id: "#{prefix}-pix", amount_cents: 1_000)
    PixPayments::Settle.call(organization:, pix_payment:)
    [ organization, wallet, pix_payment ]
  end

  def create_operator(prefix)
    User.create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "strong-password-123",
      role: "admin"
    )
  end
end
