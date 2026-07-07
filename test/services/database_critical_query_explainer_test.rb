require "test_helper"

class DatabaseCriticalQueryExplainerTest < ActiveSupport::TestCase
  test "returns explain plans for critical financial queries" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "explain-funding", amount_cents: 10_000)
    JournalEntry.where(organization:).find_each do |journal_entry|
      Analytics::LedgerAnalyticsProjector.call(journal_entry:)
    end

    explains = Database::CriticalQueryExplainer.call(organization:, analyze: false)

    assert_equal %i[audit_chain_tail ledger_analytics_wallet_daily outbox_publishable reconciliation_accounts wallet_statement].sort, explains.map { |explain| explain.fetch(:name) }.sort
    explains.each do |explain|
      assert explain.fetch(:sql).present?
      assert explain.fetch(:plan).present?
    end
  end
end
