require "test_helper"

class LedgerJournalPosterTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @source_wallet = create_wallet(organization: @organization)
    @destination_wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "initial-funding",
      amount_cents: 10_000
    )
  end

  test "posts balanced double-entry lines and updates wallet projections" do
    journal = Ledger::JournalPoster.call(
      organization: @organization,
      event_type: "test.transfer",
      lines: [
        { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
        { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
      ]
    )

    assert journal.balanced?
    assert_equal 7_500, @source_wallet.balance_projection.reload.available_cents
    assert_equal 2_500, @destination_wallet.balance_projection.reload.available_cents
  end

  test "rejects unbalanced journal entries before persistence" do
    assert_raises(Errors::ValidationError) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "test.bad_entry",
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_400, currency: "BRL" }
        ]
      )
    end

    assert_empty JournalEntry.where(event_type: "test.bad_entry")
  end
end
