require "test_helper"

class DatabaseCriticalQueryExplainerTest < ActiveSupport::TestCase
  test "returns explain plans for critical financial queries" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "explain-funding", amount_cents: 10_000)

    explains = Database::CriticalQueryExplainer.call(organization:, analyze: false)

    assert_equal %i[audit_chain_tail outbox_publishable reconciliation_accounts wallet_statement].sort, explains.map { |explain| explain.fetch(:name) }.sort
    explains.each do |explain|
      assert explain.fetch(:sql).present?
      assert explain.fetch(:plan).present?
    end
  end
end
