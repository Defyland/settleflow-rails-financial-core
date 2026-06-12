require "test_helper"

class WalletsStatementBuilderTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    @amounts = [ 100, 200, 300, 400, 500 ]
    @amounts.each_with_index do |amount, index|
      fund_wallet(
        organization: @organization,
        wallet: @wallet,
        external_id: "stmt-funding-#{index}",
        amount_cents: amount
      )
    end
  end

  test "windows to the requested limit and anchors running balance to the current projection" do
    statement = Wallets::StatementBuilder.call(wallet: @wallet, limit: 2)

    available = @wallet.balance_projection.reload.available_cents
    assert_equal @amounts.sum, available

    # Only the window is materialized, newest first, even though five lines exist.
    assert_equal 2, statement.size
    assert_equal [ 500, 400 ], statement.map(&:delta_cents)
    # Running balance is correct for a partial window: newest equals the full
    # available balance, the next steps back by the newest delta.
    assert_equal [ available, available - 500 ], statement.map(&:running_available_cents)
  end

  test "single-line window still reports the full available balance" do
    statement = Wallets::StatementBuilder.call(wallet: @wallet, limit: 1)

    assert_equal 1, statement.size
    assert_equal @amounts.sum, statement.first.running_available_cents
  end

  # Query-shape proof: the running balance is derived backward from an aggregate,
  # so the ledger-line *row load* must be bounded by LIMIT, never a full-history
  # materialization. Aggregate (SUM) scans are allowed; row loads are not.
  test "loads ledger line rows bounded by LIMIT, not the full history" do
    captured = []
    subscriber = ->(_name, _start, _finish, _id, payload) { captured << payload[:sql] }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      Wallets::StatementBuilder.call(wallet: @wallet, limit: 2)
    end

    row_loads = captured.select do |sql|
      sql.include?('FROM "ledger_lines"') && sql !~ /SELECT\s+(SUM|COUNT|MAX|MIN|AVG)\(/i
    end

    assert row_loads.any?, "expected at least one ledger_lines row load"
    row_loads.each do |sql|
      assert_match(/\bLIMIT\b/i, sql, "unbounded ledger_lines row load: #{sql}")
    end
  end
end
