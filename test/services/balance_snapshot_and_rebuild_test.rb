require "test_helper"

class BalanceSnapshotAndRebuildTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
    fund_wallet(organization: @organization, wallet: @wallet, external_id: "snapshot-funding", amount_cents: 10_000)
  end

  test "captures daily balance snapshots with ledger comparison" do
    snapshots = BalanceSnapshots::Capture.call(
      organization: @organization,
      captured_on: Date.new(2026, 6, 2),
      source: "test_capture"
    )

    snapshot = snapshots.fetch(0)
    assert_equal @wallet.public_id, snapshot.wallet.public_id
    assert_equal 10_000, snapshot.available_cents
    assert_equal 10_000, snapshot.ledger_available_cents
    assert_equal 0, snapshot.difference_cents
    assert_equal "test_capture", snapshot.source

    repeated = BalanceSnapshots::Capture.call(organization: @organization, captured_on: Date.new(2026, 6, 2))
    assert_equal snapshot.id, repeated.fetch(0).id
    assert_equal 1, @organization.balance_snapshots.count
  end

  test "rebuilds projection from ledger in dry-run and apply modes" do
    @wallet.balance_projection.reload.update!(available_cents: 9_000)

    dry_run = BalanceProjections::Rebuilder.call(organization: @organization, wallet: @wallet).fetch(0)
    assert_equal 9_000, dry_run.current_available_cents
    assert_equal 10_000, dry_run.rebuilt_available_cents
    assert_equal(-1_000, dry_run.difference_cents)
    assert_equal 9_000, @wallet.balance_projection.reload.available_cents

    applied = BalanceProjections::Rebuilder.call(organization: @organization, wallet: @wallet, apply: true).fetch(0)
    assert_equal 10_000, applied.rebuilt_available_cents
    assert_equal 10_000, @wallet.balance_projection.reload.available_cents
  end
end
