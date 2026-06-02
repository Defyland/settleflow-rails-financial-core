require "test_helper"

class DatabaseConsistencyVerifierTest < ActiveSupport::TestCase
  test "passes for balanced ledger and rebuilt projections" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "consistency-funding", amount_cents: 5_000)

    checks = Database::ConsistencyVerifier.call(organizations: Organization.where(id: organization.id))

    assert checks.all?(&:ok), checks.map { |check| [ check.name, check.details ] }.inspect
    outbox_guard_check = checks.find { |check| check.name == :outbox_evidence_guards }
    assert outbox_guard_check.details.fetch(:aggregate_function_present)
    assert_empty outbox_guard_check.details.fetch(:missing_constraints)
    assert_empty outbox_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, outbox_guard_check.details.fetch(:aggregate_evidence_mismatches)
    assert_equal %w[
      outbox_events_delivery_state_check
      outbox_events_payload_sha256_hex_check
      outbox_events_status_check
    ], outbox_guard_check.details.fetch(:present_constraints)
    assert_equal %w[
      outbox_events_aggregate_evidence_before_write
      outbox_events_prevent_evidence_mutation
    ], outbox_guard_check.details.fetch(:present_triggers)
    idempotency_guard_check = checks.find { |check| check.name == :idempotency_evidence_guards }
    assert idempotency_guard_check.details.fetch(:mutation_trigger_present)
    assert_empty idempotency_guard_check.details.fetch(:missing_constraints)
    assert_equal %w[
      idempotency_keys_identity_present_check
      idempotency_keys_request_hash_sha256_check
      idempotency_keys_response_state_check
      idempotency_keys_status_check
    ], idempotency_guard_check.details.fetch(:present_constraints)
    processed_event_guard_check = checks.find { |check| check.name == :processed_event_evidence_guards }
    assert processed_event_guard_check.details.fetch(:mutation_trigger_present)
    assert_empty processed_event_guard_check.details.fetch(:missing_constraints)
    assert_equal 0, processed_event_guard_check.details.fetch(:outbox_evidence_mismatches)
    assert_equal %w[
      processed_events_payload_sha256_hex_check
      processed_events_state_evidence_check
      processed_events_status_check
    ], processed_event_guard_check.details.fetch(:present_constraints)
    balance_guard_check = checks.find { |check| check.name == :balance_evidence_guards }
    assert_empty balance_guard_check.details.fetch(:missing_constraints)
    assert_empty balance_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, balance_guard_check.details.fetch(:projection_wallet_mismatches)
    assert_equal 0, balance_guard_check.details.fetch(:snapshot_evidence_mismatches)
    assert_equal %w[
      balance_projections_wallet_evidence_before_write
      balance_snapshots_prevent_evidence_mutation
    ], balance_guard_check.details.fetch(:present_triggers)
    operator_approval_guard_check = checks.find { |check| check.name == :operator_approval_evidence_guards }
    assert_empty operator_approval_guard_check.details.fetch(:missing_constraints)
    assert_empty operator_approval_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, operator_approval_guard_check.details.fetch(:evidence_mismatches)
    assert_equal [ "operator_approvals_prevent_evidence_mutation" ], operator_approval_guard_check.details.fetch(:present_triggers)
    reconciliation_guard_check = checks.find { |check| check.name == :reconciliation_evidence_guards }
    assert_empty reconciliation_guard_check.details.fetch(:missing_constraints)
    assert_empty reconciliation_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, reconciliation_guard_check.details.fetch(:evidence_mismatches)
    assert_equal %w[
      reconciliation_rows_evidence_after_write
      reconciliation_rows_prevent_evidence_mutation
      reconciliation_runs_evidence_after_write
      reconciliation_runs_prevent_evidence_mutation
    ], reconciliation_guard_check.details.fetch(:present_triggers)
    state_guard_check = checks.find { |check| check.name == :financial_state_evidence_guards }
    assert_empty state_guard_check.details.fetch(:missing_triggers)
    assert_equal %w[
      fundings_state_evidence_after_write
      med_cases_state_evidence_after_write
      payouts_state_evidence_after_write
      pix_payments_state_evidence_after_write
      refunds_state_evidence_after_write
      split_entries_state_evidence_after_write
      split_payments_state_evidence_after_write
      transfers_state_evidence_after_write
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
