require "test_helper"

class DatabaseConsistencyVerifierTest < ActiveSupport::TestCase
  test "passes for balanced ledger and rebuilt projections" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "consistency-funding", amount_cents: 5_000)

    checks = Database::ConsistencyVerifier.call(organizations: Organization.where(id: organization.id))

    assert checks.all?(&:ok), checks.map { |check| [ check.name, check.details ] }.inspect
    outbox_guard_check = checks.find { |check| check.name == :outbox_evidence_guards }
    assert outbox_guard_check.details.fetch(:mutation_trigger_present)
    assert outbox_guard_check.details.fetch(:payload_hash_check_present)
    state_guard_check = checks.find { |check| check.name == :financial_state_evidence_guards }
    assert_empty state_guard_check.details.fetch(:missing_triggers)
    assert_equal %w[
      med_cases_state_evidence_after_write
      payouts_state_evidence_after_write
      pix_payments_state_evidence_after_write
      refunds_state_evidence_after_write
    ], state_guard_check.details.fetch(:present_triggers)
  end

  test "detects balance projection drift from ledger" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "consistency-drift-funding", amount_cents: 5_000)
    wallet.balance_projection.reload.update!(available_cents: 4_500)

    checks = Database::ConsistencyVerifier.call(organizations: Organization.where(id: organization.id))
    projection_check = checks.find { |check| check.name == :projection_rebuild }

    assert_not projection_check.ok
    assert_equal 1, projection_check.details.fetch(:mismatched_wallets)
    assert_equal(-500, projection_check.details.fetch(:difference_cents_sum))
  end
end
