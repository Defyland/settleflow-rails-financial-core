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
    assert outbox_guard_check.details.fetch(:med_payload_function_present)
    assert outbox_guard_check.details.fetch(:command_identity_function_present)
    assert_empty outbox_guard_check.details.fetch(:missing_constraints)
    assert_empty outbox_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, outbox_guard_check.details.fetch(:aggregate_evidence_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:mutable_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:published_legacy_command_identity_mismatches)
    assert_equal %w[
      outbox_events_delivery_state_check
      outbox_events_payload_sha256_hex_check
      outbox_events_status_check
    ], outbox_guard_check.details.fetch(:present_constraints)
    assert_equal %w[
      outbox_events_aggregate_evidence_before_write
      outbox_events_command_identity_before_write
      outbox_events_med_resolution_payload_before_write
      outbox_events_prevent_evidence_mutation
    ], outbox_guard_check.details.fetch(:present_triggers)
    idempotency_guard_check = checks.find { |check| check.name == :idempotency_evidence_guards }
    assert idempotency_guard_check.details.fetch(:mutation_trigger_present)
    assert_empty idempotency_guard_check.details.fetch(:missing_constraints)
    assert_empty idempotency_guard_check.details.fetch(:missing_command_constraints)
    assert_equal %w[
      idempotency_keys_identity_present_check
      idempotency_keys_request_hash_sha256_check
      idempotency_keys_response_state_check
      idempotency_keys_status_check
    ], idempotency_guard_check.details.fetch(:present_constraints)
    assert_equal %w[
      fundings_idempotency_key_required_check
      med_cases_idempotency_key_required_check
      payouts_idempotency_key_required_check
      pix_payments_idempotency_key_required_check
      refunds_idempotency_key_required_check
      split_payments_idempotency_key_required_check
      transfers_idempotency_key_required_check
    ], idempotency_guard_check.details.fetch(:present_command_constraints)
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
    assert state_guard_check.details.fetch(:aggregate_function_present)
    assert state_guard_check.details.fetch(:med_resolution_functions_present)
    assert state_guard_check.details.fetch(:refund_limit_function_present)
    assert state_guard_check.details.fetch(:payout_early_settlement_function_present)
    assert_equal 0, state_guard_check.details.fetch(:refund_limit_mismatches)
    assert_equal 0, state_guard_check.details.fetch(:payout_early_settlement_mismatches)
    assert_empty state_guard_check.details.fetch(:missing_triggers)
    assert_equal %w[
      fundings_prevent_evidence_mutation
      fundings_state_evidence_after_write
      med_cases_prevent_evidence_mutation
      med_cases_state_evidence_after_write
      payouts_prevent_evidence_mutation
      payouts_state_evidence_after_write
      pix_payments_prevent_evidence_mutation
      pix_payments_refund_evidence_after_write
      pix_payments_state_evidence_after_write
      refunds_lock_pix_payment_before_write
      refunds_pix_payment_evidence_after_write
      refunds_prevent_evidence_mutation
      refunds_state_evidence_after_write
      split_entries_prevent_evidence_mutation
      split_entries_state_evidence_after_write
      split_payments_prevent_evidence_mutation
      split_payments_state_evidence_after_write
      transfers_prevent_evidence_mutation
      transfers_state_evidence_after_write
    ], state_guard_check.details.fetch(:present_triggers)
    journal_guard_check = checks.find { |check| check.name == :financial_journal_evidence_guards }
    assert journal_guard_check.details.fetch(:evidence_functions_present)
    assert_empty journal_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, journal_guard_check.details.fetch(:evidence_mismatches)
    assert_equal %w[
      fundings_journal_evidence_after_write
      journal_entries_financial_evidence_after_write
      ledger_lines_financial_evidence_after_write
      payouts_journal_evidence_after_write
      pix_payments_journal_evidence_after_write
      refunds_journal_evidence_after_write
      split_payments_journal_evidence_after_write
      transfers_journal_evidence_after_write
    ], journal_guard_check.details.fetch(:present_triggers)
    journal_taxonomy_check = checks.find { |check| check.name == :journal_event_taxonomy }
    assert journal_taxonomy_check.details.fetch(:constraint_validated)
    assert_equal JournalEntry::SUPPORTED_EVENT_TYPES, journal_taxonomy_check.details.fetch(:supported_event_types)
    assert_empty journal_taxonomy_check.details.fetch(:unknown_event_types)
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
