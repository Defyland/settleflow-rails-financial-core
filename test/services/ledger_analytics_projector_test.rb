require "test_helper"

class LedgerAnalyticsProjectorTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
  end

  test "projects posted ledger lines into a monthly partition idempotently" do
    funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "analytics-projection-funding",
      amount_cents: 12_500
    )
    journal = funding.journal_entry

    first_projection = Analytics::LedgerAnalyticsProjector.call(journal_entry: journal)
    second_projection = Analytics::LedgerAnalyticsProjector.call(journal_entry: journal)

    assert_equal 2, first_projection.size
    assert_equal first_projection.map(&:ledger_line_id).sort, second_projection.map(&:ledger_line_id).sort
    assert_equal 2, LedgerAnalyticsEvent.where(journal_entry_id: journal.id).count
    assert ActiveRecord::Base.connection.data_source_exists?(
      Analytics::LedgerAnalyticsPartitions.partition_name(journal.occurred_at.to_date)
    )
  end

  test "captures signed wallet movement without mutating ledger truth" do
    funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "analytics-signed-funding",
      amount_cents: 7_500
    )

    Analytics::LedgerAnalyticsProjector.call(journal_entry: funding.journal_entry)

    wallet_rows = LedgerAnalyticsEvent.where(wallet_id: @wallet.id)

    assert_equal 1, wallet_rows.count
    assert_equal 7_500, wallet_rows.sole.signed_amount_cents

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      wallet_rows.sole.update!(metadata: { corrected: true })
    end
  end
end
