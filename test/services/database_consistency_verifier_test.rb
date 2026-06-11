require "test_helper"

class DatabaseConsistencyVerifierTest < ActiveSupport::TestCase
  test "passes every seeded check for a balanced organization" do
    checks = seeded_checks

    assert checks.all?(&:ok), checks.map { |check| [ check.name, check.details ] }.inspect
  end

  test "reports outbox evidence guards with the expected catalog contract" do
    outbox_guard_check = check_named(seeded_checks, :outbox_evidence_guards)

    assert outbox_guard_check.details.fetch(:aggregate_function_present)
    assert outbox_guard_check.details.fetch(:med_payload_function_present)
    assert outbox_guard_check.details.fetch(:command_identity_function_present)
    assert outbox_guard_check.details.fetch(:legacy_exception_table_present)
    assert outbox_guard_check.details.fetch(:legacy_exception_functions_present)
    assert_empty outbox_guard_check.details.fetch(:missing_constraints)
    assert_empty outbox_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, outbox_guard_check.details.fetch(:aggregate_evidence_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:mutable_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:published_legacy_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:accepted_published_legacy_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:unaccepted_published_legacy_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:legacy_exception_evidence_mismatches)
    assert_equal FinancialContracts::OUTBOX_EVIDENCE_CONSTRAINTS.sort, outbox_guard_check.details.fetch(:present_constraints)
    assert_equal FinancialContracts::OUTBOX_EVIDENCE_TRIGGERS.sort, outbox_guard_check.details.fetch(:present_triggers)
  end

  test "reports idempotency and processed event evidence guards separately" do
    checks = seeded_checks
    idempotency_guard_check = check_named(checks, :idempotency_evidence_guards)
    processed_event_guard_check = check_named(checks, :processed_event_evidence_guards)

    assert idempotency_guard_check.details.fetch(:mutation_trigger_present)
    assert_empty idempotency_guard_check.details.fetch(:missing_constraints)
    assert_empty idempotency_guard_check.details.fetch(:missing_command_constraints)
    assert_equal %w[
      idempotency_keys_identity_present_check
      idempotency_keys_request_hash_sha256_check
      idempotency_keys_response_state_check
      idempotency_keys_status_check
    ], idempotency_guard_check.details.fetch(:present_constraints)
    assert_equal FinancialContracts::IDEMPOTENCY_REQUIRED_COMMAND_CONSTRAINTS.values.sort,
      idempotency_guard_check.details.fetch(:present_command_constraints)

    assert processed_event_guard_check.details.fetch(:mutation_trigger_present)
    assert_empty processed_event_guard_check.details.fetch(:missing_constraints)
    assert_equal 0, processed_event_guard_check.details.fetch(:outbox_evidence_mismatches)
    assert_equal %w[
      processed_events_payload_sha256_hex_check
      processed_events_state_evidence_check
      processed_events_status_check
    ], processed_event_guard_check.details.fetch(:present_constraints)
  end

  test "reports balance, approval, and reconciliation evidence guards separately" do
    checks = seeded_checks
    balance_guard_check = check_named(checks, :balance_evidence_guards)
    operator_approval_guard_check = check_named(checks, :operator_approval_evidence_guards)
    reconciliation_guard_check = check_named(checks, :reconciliation_evidence_guards)

    assert balance_guard_check.details.fetch(:write_gate_function_present)
    assert_empty balance_guard_check.details.fetch(:missing_constraints)
    assert_empty balance_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, balance_guard_check.details.fetch(:projection_wallet_mismatches)
    assert_equal 0, balance_guard_check.details.fetch(:snapshot_evidence_mismatches)
    assert_equal %w[
      balance_projections_amount_write_gate_before_update
      balance_projections_wallet_evidence_before_write
      balance_snapshots_prevent_evidence_mutation
    ], balance_guard_check.details.fetch(:present_triggers)

    assert_empty operator_approval_guard_check.details.fetch(:missing_constraints)
    assert_empty operator_approval_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, operator_approval_guard_check.details.fetch(:evidence_mismatches)
    assert_equal [ "operator_approvals_prevent_evidence_mutation" ], operator_approval_guard_check.details.fetch(:present_triggers)

    assert_empty reconciliation_guard_check.details.fetch(:missing_constraints)
    assert_empty reconciliation_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, reconciliation_guard_check.details.fetch(:evidence_mismatches)
    assert_equal %w[
      reconciliation_rows_evidence_after_write
      reconciliation_rows_prevent_evidence_mutation
      reconciliation_runs_evidence_after_write
      reconciliation_runs_prevent_evidence_mutation
    ], reconciliation_guard_check.details.fetch(:present_triggers)
  end

  test "reports financial state and journal evidence guards separately" do
    checks = seeded_checks
    state_guard_check = check_named(checks, :financial_state_evidence_guards)
    journal_guard_check = check_named(checks, :financial_journal_evidence_guards)
    journal_taxonomy_check = check_named(checks, :journal_event_taxonomy)

    assert state_guard_check.details.fetch(:aggregate_function_present)
    assert state_guard_check.details.fetch(:med_resolution_functions_present)
    assert state_guard_check.details.fetch(:refund_limit_function_present)
    assert state_guard_check.details.fetch(:payout_early_settlement_function_present)
    assert_equal 0, state_guard_check.details.fetch(:refund_limit_mismatches)
    assert_equal 0, state_guard_check.details.fetch(:payout_early_settlement_mismatches)
    assert state_guard_check.details.fetch(:unique_split_destination_index_present)
    assert_equal 0, state_guard_check.details.fetch(:duplicate_split_destination_rows)
    assert_empty state_guard_check.details.fetch(:missing_triggers)
    assert_equal FinancialContracts::FINANCIAL_STATE_EVIDENCE_TRIGGERS.sort,
      state_guard_check.details.fetch(:present_triggers)

    assert journal_guard_check.details.fetch(:evidence_functions_present)
    assert_empty journal_guard_check.details.fetch(:missing_triggers)
    assert_equal 0, journal_guard_check.details.fetch(:evidence_mismatches)
    assert_equal FinancialContracts::FINANCIAL_JOURNAL_EVIDENCE_TRIGGERS.sort,
      journal_guard_check.details.fetch(:present_triggers)

    assert journal_taxonomy_check.details.fetch(:constraint_validated)
    assert_equal JournalEntry::SUPPORTED_EVENT_TYPES, journal_taxonomy_check.details.fetch(:supported_event_types)
    assert_empty journal_taxonomy_check.details.fetch(:unknown_event_types)
  end

  test "detects balance projection drift from ledger" do
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "consistency-drift-funding", amount_cents: 5_000)
    force_balance_projection_drift!(wallet.balance_projection, available_cents: 4_500)

    checks = Database::ConsistencyVerifier.call(organizations: Organization.where(id: organization.id))
    projection_check = checks.find { |check| check.name == :projection_rebuild }

    assert_not projection_check.ok
    assert_equal 1, projection_check.details.fetch(:mismatched_wallets)
    assert_equal(-500, projection_check.details.fetch(:difference_cents_sum))
  end

  private

  def seeded_checks
    organization = create_organization
    wallet = create_wallet(organization:)
    fund_wallet(organization:, wallet:, external_id: "consistency-funding", amount_cents: 5_000)

    Database::ConsistencyVerifier.call(organizations: Organization.where(id: organization.id))
  end

  def check_named(checks, name)
    checks.find { |check| check.name == name } || flunk("missing consistency check: #{name}")
  end
end
