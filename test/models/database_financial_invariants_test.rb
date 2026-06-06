require "test_helper"

class DatabaseFinancialInvariantsTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @wallet = create_wallet(organization: @organization)
  end

  test "database rejects negative balance projections" do
    assert_raises(ActiveRecord::StatementInvalid) do
      @wallet.balance_projection.update_columns(available_cents: -1)
    end
  end

  test "database rejects direct positive balance projection amount tampering" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-projection-tamper",
      amount_cents: 1_000
    )

    assert_database_constraint_violation { @wallet.balance_projection.reload.update_columns(available_cents: 999) }
  end

  test "database rejects balance projection wallet evidence drift" do
    other_organization = create_organization
    other_wallet = create_wallet(organization: other_organization)
    projection = @wallet.balance_projection

    assert_database_constraint_violation { projection.update_columns(organization_id: other_organization.id) }
    assert_database_constraint_violation { projection.update_columns(wallet_id: other_wallet.id) }
    assert_database_constraint_violation { projection.update_columns(currency: "USD") }
  end

  test "database rejects balance snapshot evidence tampering" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-snapshot-funding",
      amount_cents: 100
    )
    snapshot = BalanceSnapshots::Capture.call(
      organization: @organization,
      captured_on: Date.current,
      source: "db_invariant"
    ).sole
    other_organization = create_organization
    other_wallet = create_wallet(organization: other_organization)

    assert_database_constraint_violation { snapshot.update_columns(difference_cents: snapshot.difference_cents + 1) }
    assert_database_constraint_violation { snapshot.update_columns(wallet_id: other_wallet.id) }
    assert_database_constraint_violation { snapshot.update_columns(organization_id: other_organization.id) }
    assert_database_constraint_violation { BalanceSnapshot.where(id: snapshot.id).delete_all }
    assert_database_constraint_violation do
      BalanceSnapshot.insert!({
        organization_id: @organization.id,
        wallet_id: @wallet.id,
        currency: @wallet.currency,
        captured_on: Date.current.next_day,
        captured_at: Time.current,
        available_cents: 100,
        pending_cents: 0,
        blocked_cents: 0,
        ledger_available_cents: 100,
        difference_cents: 1,
        source: "db_invariant",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects direct operator approval evidence tampering" do
    requester = User.create!(
      email_address: "requester-#{SecureRandom.hex(4)}@example.com",
      password: "strong-password-123",
      role: "admin"
    )
    checker = User.create!(
      email_address: "checker-#{SecureRandom.hex(4)}@example.com",
      password: "strong-password-123",
      role: "admin"
    )
    approval = @organization.operator_approvals.create!(
      action: "pix_payment.settle",
      subject_type: "PixPayment",
      subject_id: 1,
      requested_by: requester,
      reason: "db_invariant"
    )

    assert_database_constraint_violation { approval.update_columns(status: "approved") }
    approval.reload
    assert_database_constraint_violation { approval.update_columns(approved_by_id: requester.id, approved_at: Time.current) }
    assert_database_constraint_violation do
      OperatorApproval.insert!({
        organization_id: @organization.id,
        action: "pix_payment.reverse",
        subject_type: "PixPayment",
        subject_id: 2,
        status: "approved",
        requested_by_id: requester.id,
        approved_by_id: checker.id,
        approved_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      OperatorApproval.insert!({
        organization_id: @organization.id,
        action: "",
        subject_type: "PixPayment",
        subject_id: 3,
        status: "pending",
        requested_by_id: requester.id,
        created_at: Time.current,
        updated_at: Time.current
      })
    end

    approval.update!(status: "approved", approved_by: checker, approved_at: Time.current)

    assert_database_constraint_violation { approval.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { OperatorApproval.where(id: approval.id).delete_all }
  end

  test "database rejects direct reconciliation evidence tampering" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-reconciliation-funding",
      amount_cents: 500
    )
    run = Reconciliation::Run.call(
      organization: @organization,
      provider: "db-invariant-provider",
      statement_date: Date.current,
      provider_balance_cents: 400
    )
    row = run.reconciliation_rows.find_by!(row_type: "cash_balance")

    assert_database_constraint_violation { run.update_columns(discrepancy_cents: run.discrepancy_cents + 1) }
    assert_database_constraint_violation { run.update_columns(status: "matched") }
    assert_database_constraint_violation { ReconciliationRun.where(id: run.id).delete_all }
    assert_database_constraint_violation { row.update_columns(status: "matched", provider_amount_cents: row.ledger_amount_cents, difference_cents: 0) }
    assert_database_constraint_violation { ReconciliationRow.where(id: row.id).delete_all }
    assert_database_constraint_violation do
      ReconciliationRun.insert!({
        organization_id: @organization.id,
        provider: "db-invariant-direct-recon",
        statement_date: Date.current.next_day,
        provider_balance_cents: 0,
        ledger_balance_cents: 0,
        discrepancy_cents: 0,
        status: "matched",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects journal entries without command identity" do
    assert_raises(ActiveRecord::StatementInvalid) do
      JournalEntry.insert!({
        organization_id: @organization.id,
        event_type: "wallet.funded",
        reference_type: "Funding",
        reference_id: -1,
        occurred_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects financial command rows without idempotency evidence" do
    destination_wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-command-identity-base-funding",
      amount_cents: 1_000
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-command-identity-pix-source",
      amount_cents: 100
    )

    command_rows = [
      [
        Funding,
        {
          organization_id: @organization.id,
          wallet_id: @wallet.id,
          external_id: "db-invariant-command-identity-funding",
          amount_cents: 100,
          currency: "BRL",
          status: "failed",
          failure_code: "missing_idempotency"
        }
      ],
      [
        Transfer,
        {
          organization_id: @organization.id,
          source_wallet_id: @wallet.id,
          destination_wallet_id: destination_wallet.id,
          external_id: "db-invariant-command-identity-transfer",
          amount_cents: 100,
          currency: "BRL",
          status: "failed",
          failure_code: "missing_idempotency"
        }
      ],
      [
        SplitPayment,
        {
          organization_id: @organization.id,
          source_wallet_id: @wallet.id,
          external_id: "db-invariant-command-identity-split",
          total_amount_cents: 100,
          currency: "BRL",
          status: "failed",
          failure_code: "missing_idempotency"
        }
      ],
      [
        PixPayment,
        {
          organization_id: @organization.id,
          wallet_id: @wallet.id,
          external_id: "db-invariant-command-identity-pix",
          pix_key: "db-invariant-command-identity@example.com",
          receiver_name: "Receiver",
          amount_cents: 100,
          currency: "BRL",
          status: "failed",
          risk_score: 0,
          failure_code: "missing_idempotency"
        }
      ],
      [
        Payout,
        {
          organization_id: @organization.id,
          wallet_id: @wallet.id,
          external_id: "db-invariant-command-identity-payout",
          amount_cents: 100,
          currency: "BRL",
          status: "failed",
          settlement_delay_days: 0,
          settlement_due_on: Date.current,
          destination_kind: "bank_account",
          destination_reference: "bank-account",
          failure_code: "missing_idempotency"
        }
      ],
      [
        Refund,
        {
          organization_id: @organization.id,
          wallet_id: @wallet.id,
          pix_payment_id: pix_payment.id,
          external_id: "db-invariant-command-identity-refund",
          amount_cents: 100,
          currency: "BRL",
          status: "failed",
          reason: "customer_request",
          failure_code: "missing_idempotency"
        }
      ],
      [
        MedCase,
        {
          organization_id: @organization.id,
          pix_payment_id: pix_payment.id,
          external_id: "db-invariant-command-identity-med",
          amount_cents: 100,
          currency: "BRL",
          status: "opened",
          reason: "fraud_report",
          opened_at: Time.current
        }
      ]
    ]

    command_rows.each do |model, attributes|
      assert_database_constraint_violation do
        model.insert!(attributes.merge(
          idempotency_key: nil,
          created_at: Time.current,
          updated_at: Time.current
        ))
      end

      assert_database_constraint_violation do
        model.insert!(attributes.merge(
          idempotency_key: " ",
          created_at: Time.current,
          updated_at: Time.current
        ))
      end
    end
  end

  test "database rejects direct unbalanced journal inserts" do
    destination_wallet = create_wallet(organization: @organization)
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction do
        transfer = @organization.transfers.create!(
          source_wallet: @wallet,
          destination_wallet:,
          external_id: "db-invariant-unbalanced-transfer",
          amount_cents: 100,
          currency: "BRL",
          idempotency_key: "db-invariant-unbalanced-transfer"
        )
        journal_id = JournalEntry.insert!({
          organization_id: @organization.id,
          event_type: "wallet.transfer.posted",
          reference_type: "Transfer",
          reference_id: transfer.id,
          idempotency_key: transfer.idempotency_key,
          occurred_at: Time.current,
          created_at: Time.current,
          updated_at: Time.current
        }).first["id"]

        LedgerLine.insert_all!([
          {
            organization_id: @organization.id,
            journal_entry_id: journal_id,
            ledger_account_id: @wallet.liability_account.id,
            direction: "debit",
            amount_cents: 100,
            currency: "BRL",
            created_at: Time.current,
            updated_at: Time.current
          },
          {
            organization_id: @organization.id,
            journal_entry_id: journal_id,
            ledger_account_id: destination_wallet.liability_account.id,
            direction: "credit",
            amount_cents: 99,
            currency: "BRL",
            created_at: Time.current,
            updated_at: Time.current
          }
        ])
        transfer.update!(journal_entry_id: journal_id)
        ActiveRecord::Base.connection.execute(
          "SET CONSTRAINTS journal_entry_balanced_after_journal_insert, journal_entry_balanced_after_line_insert IMMEDIATE"
        )
      end
    end
  end

  test "database rejects unsupported journal event types" do
    destination_wallet = create_wallet(organization: @organization)
    transfer = @organization.transfers.create!(
      source_wallet: @wallet,
      destination_wallet:,
      external_id: "db-invariant-unsupported-journal-event",
      amount_cents: 100,
      currency: "BRL",
      idempotency_key: "db-invariant-unsupported-journal-event"
    )

    assert_database_constraint_violation do
      insert_balanced_journal!(
        event_type: "manual.adjustment",
        reference_type: "Transfer",
        reference_id: transfer.id,
        idempotency_key: transfer.idempotency_key,
        debit_account: @wallet.liability_account,
        credit_account: destination_wallet.liability_account,
        amount_cents: 100
      )
    end
  end

  test "database rejects direct ledger mutation and deletion bypassing models" do
    journal = post_test_journal
    line = journal.ledger_lines.first

    assert_database_constraint_violation { journal.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { line.update_columns(amount_cents: line.amount_cents + 1) }
    assert_database_constraint_violation { LedgerLine.where(id: line.id).delete_all }
    assert_database_constraint_violation { JournalEntry.where(id: journal.id).delete_all }
  end

  test "database rejects financial journal entries that do not match aggregate evidence" do
    assert_database_constraint_violation do
      journal_id = insert_balanced_journal!(
        event_type: "wallet.funded",
        reference_type: "Funding",
        reference_id: -1,
        idempotency_key: "db-invariant-fake-financial-journal",
        debit_account: Ledger::AccountLocator.platform_cash(organization: @organization, currency: @wallet.currency),
        credit_account: @wallet.liability_account,
        amount_cents: 100
      )
      assert journal_id
    end

    assert_database_constraint_violation do
      wrong_journal_id = insert_balanced_journal!(
        event_type: "wallet.funded",
        reference_type: "Funding",
        reference_id: 0,
        idempotency_key: "db-invariant-detached-financial-journal",
        debit_account: Ledger::AccountLocator.platform_cash(organization: @organization, currency: @wallet.currency),
        credit_account: @wallet.liability_account,
        amount_cents: 100
      )
      Funding.insert!({
        organization_id: @organization.id,
        wallet_id: @wallet.id,
        journal_entry_id: wrong_journal_id,
        external_id: "db-invariant-wrong-journal-funding",
        amount_cents: 100,
        currency: @wallet.currency,
        status: "posted",
        idempotency_key: "db-invariant-wrong-journal-funding",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects direct outbox evidence tampering and deletion" do
    funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-outbox-funding",
      amount_cents: 10
    )
    event = outbox_event_for(funding, "wallet.funded")
    publish_outbox_event(event)

    assert_database_constraint_violation { event.update_columns(payload: { tampered: true }) }
    assert_database_constraint_violation { event.update_columns(event_type: "wallet.tampered") }
    assert_database_constraint_violation { event.update_columns(payload_sha256: "b" * 64) }
    assert_database_constraint_violation { event.update_columns(status: "pending") }
    assert_database_constraint_violation { OutboxEvent.where(id: event.id).delete_all }
    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "Wallet",
        aggregate_id: @wallet.id,
        event_type: "wallet.fake_published",
        status: "published",
        attempts: 1,
        published_at: Time.current,
        payload: { wallet_id: @wallet.public_id },
        payload_sha256: "a" * 64,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "Funding",
        aggregate_id: funding.id,
        event_type: "wallet.funded",
        status: "pending",
        attempts: 0,
        payload: {
          funding_id: funding.public_id,
          wallet_id: @wallet.public_id,
          amount_cents: funding.amount_cents,
          currency: funding.currency
        },
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "Funding",
        aggregate_id: funding.id,
        event_type: "wallet.fake_published",
        status: "pending",
        attempts: 0,
        payload: {
          funding_id: funding.public_id,
          wallet_id: @wallet.public_id,
          amount_cents: funding.amount_cents,
          currency: funding.currency
        },
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "Funding",
        aggregate_id: -1,
        event_type: "wallet.funded",
        status: "pending",
        attempts: 0,
        payload: {
          funding_id: SecureRandom.uuid,
          wallet_id: @wallet.public_id,
          amount_cents: funding.amount_cents,
          currency: funding.currency
        },
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "Funding",
        aggregate_id: funding.id,
        event_type: "wallet.funded",
        status: "pending",
        attempts: 0,
        payload: {
          funding_id: funding.public_id,
          wallet_id: @wallet.public_id,
          amount_cents: funding.amount_cents + 1,
          currency: funding.currency
        },
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects MED resolution outbox payload without approval and refund evidence" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-med-outbox-funding",
      amount_cents: 1_000
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-med-outbox-pix",
      amount_cents: 100
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment:,
      external_id: "db-invariant-med-outbox",
      amount_cents: 50,
      reason: "fraud_report",
      idempotency_key: "db-invariant-med-outbox"
    )
    maker = create_operator("db-med-outbox-maker")
    checker = create_operator("db-med-outbox-checker")
    MedCases::Accept.call(organization: @organization, med_case:, operator: maker, reason: "fraud_confirmed")
    approved = MedCases::Accept.call(organization: @organization, med_case:, operator: checker, reason: "fraud_confirmed").subject

    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "MedCase",
        aggregate_id: approved.id,
        event_type: "med.case.refunded",
        status: "pending",
        attempts: 0,
        payload: {
          med_case_id: approved.public_id,
          pix_payment_id: pix_payment.public_id,
          amount_cents: approved.amount_cents,
          currency: approved.currency,
          status: approved.status,
          resolved_at: approved.resolved_at.iso8601
        },
        created_at: Time.current,
        updated_at: Time.current
      })
    end

    assert_database_constraint_violation do
      OutboxEvent.insert!({
        organization_id: @organization.id,
        aggregate_type: "MedCase",
        aggregate_id: approved.id,
        event_type: "med.case.refunded",
        status: "pending",
        attempts: 0,
        payload: {
          med_case_id: approved.public_id,
          pix_payment_id: pix_payment.public_id,
          refund_id: SecureRandom.uuid,
          operator_approval_id: approved.operator_approval.public_id,
          amount_cents: approved.amount_cents,
          currency: approved.currency,
          status: approved.status,
          resolved_at: approved.resolved_at.iso8601
        },
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects malformed outbox payload hashes" do
    funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-bad-hash-funding",
      amount_cents: 10
    )
    event = outbox_event_for(funding, "wallet.funded")

    assert_database_constraint_violation { event.update_columns(payload_sha256: "not-a-sha") }
    assert_database_constraint_violation { event.update_columns(payload_sha256: "b" * 64) }
  end

  test "database accepts only immutable evidence for published legacy outbox command identity gaps" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-legacy-outbox-funding",
      amount_cents: 2_000
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-legacy-outbox-pix",
      amount_cents: 100
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    legacy_event = insert_legacy_pix_settlement_outbox_event(pix_payment)
    expected_key = FinancialContracts.pix_payment_settlement_key(pix_payment)

    assert_database_constraint_violation do
      @organization.outbox_legacy_command_identity_exceptions.create!(
        outbox_event: legacy_event,
        aggregate_type: legacy_event.aggregate_type,
        aggregate_id: legacy_event.aggregate_id,
        event_type: legacy_event.event_type,
        payload_sha256: legacy_event.payload_sha256,
        expected_idempotency_key: "wrong:#{pix_payment.id}",
        reason: "published_immutable_envelope_predates_command_identity_guard",
        accepted_at: Time.current
      )
    end

    exception = @organization.outbox_legacy_command_identity_exceptions.create!(
      outbox_event: legacy_event,
      aggregate_type: legacy_event.aggregate_type,
      aggregate_id: legacy_event.aggregate_id,
      event_type: legacy_event.event_type,
      payload_sha256: legacy_event.payload_sha256,
      expected_idempotency_key: expected_key,
      reason: "published_immutable_envelope_predates_command_identity_guard",
      accepted_at: Time.current,
      metadata: { test_evidence: true }
    )

    outbox_guard_check = Database::ConsistencyVerifier.call.find { |check| check.name == :outbox_evidence_guards }
    assert outbox_guard_check.ok, outbox_guard_check.details.inspect
    assert_equal 1, outbox_guard_check.details.fetch(:published_legacy_command_identity_mismatches)
    assert_equal 1, outbox_guard_check.details.fetch(:accepted_published_legacy_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:unaccepted_published_legacy_command_identity_mismatches)
    assert_equal 0, outbox_guard_check.details.fetch(:legacy_exception_evidence_mismatches)

    assert_database_constraint_violation { exception.update_columns(reason: "tampered") }
    assert_database_constraint_violation { OutboxLegacyCommandIdentityException.where(id: exception.id).delete_all }
  end

  test "database rejects direct processed event evidence tampering" do
    funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-processed-event-funding",
      amount_cents: 10
    )
    event = outbox_event_for(funding, "wallet.funded")
    publish_outbox_event(event)
    processed_event = @organization.processed_events.create!(
      outbox_event: event,
      processor: "clickhouse_financial_events",
      event_id: event.public_id,
      event_type: event.event_type,
      payload_sha256: event.payload_sha256,
      status: "processing"
    )

    assert_database_constraint_violation { processed_event.update_columns(event_type: "wallet.tampered") }
    assert_database_constraint_violation { processed_event.update_columns(payload_sha256: "b" * 64) }
    assert_database_constraint_violation do
      ProcessedEvent.insert!({
        organization_id: @organization.id,
        outbox_event_id: event.id,
        processor: "clickhouse_financial_events_direct",
        event_id: event.public_id,
        event_type: event.event_type,
        payload_sha256: event.payload_sha256,
        status: "processed",
        processed_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      ProcessedEvent.insert!({
        organization_id: @organization.id,
        outbox_event_id: event.id,
        processor: "clickhouse_financial_events_mismatch",
        event_id: SecureRandom.uuid,
        event_type: event.event_type,
        payload_sha256: event.payload_sha256,
        status: "processing",
        created_at: Time.current,
        updated_at: Time.current
      })
    end

    processed_event.reload
    processed_event.update!(status: "processed", processed_at: Time.current)

    assert_database_constraint_violation { processed_event.update_columns(status: "failed", processed_at: nil, error_class: "RuntimeError", last_error: "tampered") }
    assert_database_constraint_violation { ProcessedEvent.where(id: processed_event.id).delete_all }
  end

  test "database rejects direct idempotency replay evidence tampering" do
    Idempotency::Runner.call(
      organization: @organization,
      key: "db-invariant-idempotency",
      request_method: "POST",
      request_path: "/v1/fundings",
      request_hash: "d" * 64
    ) do
      Idempotency::Response.new(status: 201, body: { data: { id: "first-response" } }, replayed: false)
    end
    idempotency_key = @organization.idempotency_keys.find_by!(key: "db-invariant-idempotency")

    assert idempotency_key.succeeded?
    assert_database_constraint_violation { idempotency_key.update_columns(request_hash: "e" * 64) }
    assert_database_constraint_violation { idempotency_key.update_columns(status: "processing", response_status: nil, locked_at: Time.current) }
    assert_database_constraint_violation { IdempotencyKey.where(id: idempotency_key.id).delete_all }
    assert_database_constraint_violation do
      IdempotencyKey.insert!({
        organization_id: @organization.id,
        key: "db-invariant-bad-idempotency-hash",
        request_method: "POST",
        request_path: "/v1/fundings",
        request_hash: "not-a-sha",
        status: "processing",
        locked_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
    assert_database_constraint_violation do
      IdempotencyKey.insert!({
        organization_id: @organization.id,
        key: "db-invariant-direct-success-idempotency",
        request_method: "POST",
        request_path: "/v1/fundings",
        request_hash: "f" * 64,
        status: "succeeded",
        response_status: 201,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects direct financial status changes without journal evidence" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-state-funding",
      amount_cents: 10
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-pix-state",
      amount_cents: 1
    )
    payout = Payouts::Create.call(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-payout-state",
      amount_cents: 1,
      settlement_delay_days: 0,
      destination_reference: "bank-account",
      idempotency_key: "db-invariant-payout-state"
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    refund = Refunds::Create.call(
      organization: @organization,
      pix_payment:,
      external_id: "db-invariant-refund-state",
      amount_cents: 1,
      reason: "customer_request",
      idempotency_key: "db-invariant-refund-state"
    )
    med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment:,
      external_id: "db-invariant-med-state",
      amount_cents: 1,
      reason: "fraud_report",
      idempotency_key: "db-invariant-med-state"
    )

    assert_database_constraint_violation { payout.update_columns(status: "settled", settled_at: Time.current) }
    assert_database_constraint_violation { refund.update_columns(journal_entry_id: nil) }
    assert_database_constraint_violation { med_case.update_columns(status: "refunded", resolved_at: Time.current) }
    assert_database_constraint_violation { pix_payment.update_columns(status: "reversed", reversed_at: Time.current, reversal_reason: "tampered") }
  end

  test "database rejects direct early payout settlement without maker-checker evidence" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-early-payout-funding",
      amount_cents: 1_000
    )
    payout = Payouts::Create.call(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-early-payout",
      amount_cents: 100,
      settlement_delay_days: 2,
      destination_reference: "bank-account",
      idempotency_key: "db-invariant-early-payout"
    )

    assert_database_constraint_violation do
      journal_id = insert_balanced_journal!(
        event_type: "payout.settled",
        reference_type: "Payout",
        reference_id: payout.id,
        idempotency_key: FinancialContracts.payout_settlement_key(payout),
        debit_account: Ledger::AccountLocator.payout_clearing(organization: @organization, currency: payout.currency),
        credit_account: Ledger::AccountLocator.platform_cash(organization: @organization, currency: payout.currency),
        amount_cents: payout.amount_cents
      )
      payout.update_columns(
        status: "settled",
        settlement_journal_entry_id: journal_id,
        settled_at: Time.current
      )
    end
  end

  test "database rejects MED resolution with mismatched refund evidence" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-med-approval-funding",
      amount_cents: 1_000
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-med-approval-pix",
      amount_cents: 100
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment:,
      external_id: "db-invariant-med-approval",
      amount_cents: 50,
      reason: "fraud_report",
      idempotency_key: "db-invariant-med-approval"
    )
    wrong_refund = Refunds::Create.call(
      organization: @organization,
      pix_payment:,
      external_id: "db-invariant-med-wrong-refund",
      amount_cents: 25,
      reason: "customer_request",
      idempotency_key: "db-invariant-med-wrong-refund"
    )
    maker = create_operator("db-med-maker")
    checker = create_operator("db-med-checker")
    approval = @organization.operator_approvals.create!(
      action: "med_case.accept",
      subject_type: "MedCase",
      subject_id: med_case.id,
      requested_by: maker,
      reason: "db_invariant"
    )
    approval.update!(status: "approved", approved_by: checker, approved_at: Time.current)

    assert_database_constraint_violation do
      med_case.update_columns(
        status: "refunded",
        refund_id: wrong_refund.id,
        operator_approval_id: approval.id,
        resolved_at: Time.current
      )
    end
  end

  test "database rejects direct over-refund and reversal after settled refund evidence" do
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-refund-limit-funding",
      amount_cents: 1_000
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-refund-limit-pix",
      amount_cents: 100
    )
    PixPayments::Settle.call(organization: @organization, pix_payment:)
    Refunds::Create.call(
      organization: @organization,
      pix_payment:,
      external_id: "db-invariant-refund-limit-first",
      amount_cents: 60,
      reason: "customer_request",
      idempotency_key: "db-invariant-refund-limit-first"
    )

    assert_database_constraint_violation do
      insert_direct_refund_with_journal!(
        pix_payment:,
        external_id: "db-invariant-refund-limit-over",
        amount_cents: 41,
        idempotency_key: "db-invariant-refund-limit-over"
      )
    end

    assert_database_constraint_violation do
      journal_id = insert_balanced_journal!(
        event_type: "pix.payment.reversed",
        reference_type: "PixPayment",
        reference_id: pix_payment.id,
        idempotency_key: "pix_payment.reverse:#{pix_payment.id}",
        debit_account: Ledger::AccountLocator.platform_cash(organization: @organization, currency: "BRL"),
        credit_account: @wallet.liability_account,
        amount_cents: pix_payment.amount_cents
      )
      pix_payment.update_columns(
        status: "reversed",
        reversal_journal_entry_id: journal_id,
        reversed_at: Time.current,
        reversal_reason: "direct_reversal_after_refund"
      )
    end
  end

  test "database rejects direct wallet command state and split entry tampering" do
    destination_one = create_wallet(organization: @organization)
    destination_two = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-wallet-command-funding",
      amount_cents: 20
    )
    funding = @organization.fundings.find_by!(external_id: "db-invariant-wallet-command-funding")
    transfer = Transfers::Create.call(
      organization: @organization,
      source_wallet: @wallet,
      destination_wallet: destination_one,
      external_id: "db-invariant-transfer-state",
      amount_cents: 1,
      idempotency_key: "db-invariant-transfer-state"
    )
    split_payment = SplitPayments::Create.call(
      organization: @organization,
      source_wallet: @wallet,
      external_id: "db-invariant-split-state",
      entries: [
        { destination_wallet: destination_one, amount_cents: 2 },
        { destination_wallet: destination_two, amount_cents: 3 }
      ],
      idempotency_key: "db-invariant-split-state"
    )
    split_entry = split_payment.split_entries.first

    assert_database_constraint_violation { funding.update_columns(journal_entry_id: nil) }
    assert_database_constraint_violation { funding.update_columns(status: "failed", failure_code: nil) }
    assert_database_constraint_violation { transfer.update_columns(journal_entry_id: nil) }
    assert_database_constraint_violation { transfer.update_columns(status: "reversed") }
    assert_database_constraint_violation { split_payment.update_columns(total_amount_cents: split_payment.total_amount_cents + 1) }
    assert_database_constraint_violation { split_entry.update_columns(amount_cents: split_entry.amount_cents + 1) }
    assert_database_constraint_violation { split_entry.update_columns(destination_wallet_id: split_payment.source_wallet_id) }
    assert_database_constraint_violation do
      SplitEntry.insert!({
        organization_id: @organization.id,
        split_payment_id: split_payment.id,
        destination_wallet_id: destination_one.id,
        amount_cents: 1,
        currency: split_payment.currency,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects financial aggregate mutation and deletion after evidence" do
    destination_one = create_wallet(organization: @organization)
    destination_two = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-aggregate-base-funding",
      amount_cents: 20_000
    )
    funding = fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-aggregate-funding",
      amount_cents: 100
    )
    transfer = Transfers::Create.call(
      organization: @organization,
      source_wallet: @wallet,
      destination_wallet: destination_one,
      external_id: "db-invariant-aggregate-transfer",
      amount_cents: 100,
      idempotency_key: "db-invariant-aggregate-transfer"
    )
    split_payment = SplitPayments::Create.call(
      organization: @organization,
      source_wallet: @wallet,
      external_id: "db-invariant-aggregate-split",
      entries: [
        { destination_wallet: destination_one, amount_cents: 50 },
        { destination_wallet: destination_two, amount_cents: 50 }
      ],
      idempotency_key: "db-invariant-aggregate-split"
    )
    split_entry = split_payment.split_entries.first
    payout = Payouts::Create.call(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-aggregate-payout",
      amount_cents: 100,
      settlement_delay_days: 0,
      destination_reference: "bank-account",
      idempotency_key: "db-invariant-aggregate-payout"
    )
    pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-aggregate-pix",
      amount_cents: 100
    )
    refundable_pix_payment = create_pix_payment(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-aggregate-refund-pix",
      amount_cents: 100
    )
    PixPayments::Settle.call(organization: @organization, pix_payment: refundable_pix_payment)
    refund = Refunds::Create.call(
      organization: @organization,
      pix_payment: refundable_pix_payment,
      external_id: "db-invariant-aggregate-refund",
      amount_cents: 50,
      reason: "customer_request",
      idempotency_key: "db-invariant-aggregate-refund"
    )
    med_case = MedCases::Open.call(
      organization: @organization,
      pix_payment: refundable_pix_payment,
      external_id: "db-invariant-aggregate-med",
      amount_cents: 50,
      reason: "fraud_report",
      idempotency_key: "db-invariant-aggregate-med"
    )

    assert_database_constraint_violation { funding.update_columns(amount_cents: funding.amount_cents + 1) }
    assert_database_constraint_violation { Funding.where(id: funding.id).delete_all }
    assert_database_constraint_violation { transfer.update_columns(source_wallet_id: destination_two.id) }
    assert_database_constraint_violation { Transfer.where(id: transfer.id).delete_all }
    assert_database_constraint_violation { split_payment.update_columns(external_id: "tampered") }
    assert_database_constraint_violation { split_entry.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { SplitEntry.where(id: split_entry.id).delete_all }
    assert_database_constraint_violation { payout.update_columns(destination_reference: "tampered") }
    assert_database_constraint_violation { Payout.where(id: payout.id).delete_all }
    assert_database_constraint_violation { pix_payment.update_columns(amount_cents: pix_payment.amount_cents + 1) }
    assert_database_constraint_violation { pix_payment.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { PixPayment.where(id: pix_payment.id).delete_all }
    assert_database_constraint_violation { refund.update_columns(reason: "tampered") }
    assert_database_constraint_violation { Refund.where(id: refund.id).delete_all }
    assert_database_constraint_violation { med_case.update_columns(amount_cents: med_case.amount_cents + 1) }
    assert_database_constraint_violation { med_case.update_columns(metadata: { tampered: true }) }
    assert_database_constraint_violation { MedCase.where(id: med_case.id).delete_all }
  end

  test "database rejects ledger lines whose account belongs to another organization" do
    journal = post_test_journal
    other_organization = create_organization
    other_wallet = create_wallet(organization: other_organization)

    assert_database_constraint_violation do
      LedgerLine.insert!({
        organization_id: @organization.id,
        journal_entry_id: journal.id,
        ledger_account_id: other_wallet.liability_account.id,
        direction: "credit",
        amount_cents: 1,
        currency: "BRL",
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  private

  def publish_outbox_event(event)
    event.claim_for_publish!
    event.publish!(
      Outbox::DeliveryResult.new(adapter: "test", destination: "memory://outbox", message_id: "msg-#{event.public_id}"),
      payload_sha256: Outbox::Publisher.payload_sha256(Outbox::Publisher.envelope_for(event))
    )
    event.reload
  end

  def insert_legacy_pix_settlement_outbox_event(pix_payment)
    public_id = SecureRandom.uuid
    created_at = Time.current
    payload = {
      pix_payment_id: pix_payment.public_id,
      amount_cents: pix_payment.amount_cents,
      currency: pix_payment.currency
    }
    envelope = {
      id: public_id,
      event_type: "pix.payment.settled",
      aggregate_type: "PixPayment",
      aggregate_id: pix_payment.id,
      organization_id: @organization.public_id,
      payload:,
      created_at: created_at.iso8601
    }
    payload_sha256 = Outbox::Publisher.payload_sha256(envelope)

    event_id = with_disabled_legacy_outbox_insert_guards do
      OutboxEvent.insert!({
        public_id:,
        organization_id: @organization.id,
        aggregate_type: "PixPayment",
        aggregate_id: pix_payment.id,
        event_type: "pix.payment.settled",
        status: "published",
        attempts: 1,
        published_at: created_at,
        payload:,
        payload_sha256:,
        created_at:,
        updated_at: created_at
      }).first.fetch("id")
    end
    OutboxEvent.find(event_id)
  end

  def with_disabled_legacy_outbox_insert_guards
    connection = ActiveRecord::Base.connection
    connection.execute("ALTER TABLE outbox_events DISABLE TRIGGER outbox_events_command_identity_before_write")
    connection.execute("ALTER TABLE outbox_events DISABLE TRIGGER outbox_events_prevent_evidence_mutation")
    yield
  ensure
    connection.execute("ALTER TABLE outbox_events ENABLE TRIGGER outbox_events_prevent_evidence_mutation")
    connection.execute("ALTER TABLE outbox_events ENABLE TRIGGER outbox_events_command_identity_before_write")
  end

  def post_test_journal
    destination_wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @wallet,
      external_id: "db-invariant-funding-#{SecureRandom.hex(4)}",
      amount_cents: 10
    )
    transfer = Transfers::Create.call(
      organization: @organization,
      source_wallet: @wallet,
      destination_wallet:,
      external_id: "db-invariant-transfer-#{SecureRandom.hex(4)}",
      amount_cents: 1,
      idempotency_key: "db-invariant-transfer-#{SecureRandom.hex(4)}"
    )

    transfer.journal_entry
  end

  def insert_balanced_journal!(event_type:, reference_type:, reference_id:, idempotency_key:, debit_account:, credit_account:, amount_cents:)
    journal_id = JournalEntry.insert!({
      organization_id: @organization.id,
      event_type:,
      reference_type:,
      reference_id:,
      idempotency_key:,
      occurred_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current
    }).first.fetch("id")

    LedgerLine.insert_all!([
      {
        organization_id: @organization.id,
        journal_entry_id: journal_id,
        ledger_account_id: debit_account.id,
        direction: "debit",
        amount_cents:,
        currency: debit_account.currency,
        created_at: Time.current,
        updated_at: Time.current
      },
      {
        organization_id: @organization.id,
        journal_entry_id: journal_id,
        ledger_account_id: credit_account.id,
        direction: "credit",
        amount_cents:,
        currency: credit_account.currency,
        created_at: Time.current,
        updated_at: Time.current
      }
    ])

    journal_id
  end

  def insert_direct_refund_with_journal!(pix_payment:, external_id:, amount_cents:, idempotency_key:)
    refund_id = Refund.insert!({
      organization_id: @organization.id,
      wallet_id: pix_payment.wallet_id,
      pix_payment_id: pix_payment.id,
      external_id:,
      amount_cents:,
      currency: pix_payment.currency,
      status: "settled",
      reason: "direct_refund",
      settled_at: Time.current,
      idempotency_key:,
      created_at: Time.current,
      updated_at: Time.current
    }).first.fetch("id")

    journal_id = insert_balanced_journal!(
      event_type: "refund.settled",
      reference_type: "Refund",
      reference_id: refund_id,
      idempotency_key:,
      debit_account: Ledger::AccountLocator.platform_cash(organization: @organization, currency: pix_payment.currency),
      credit_account: pix_payment.wallet.liability_account,
      amount_cents:
    )

    Refund.where(id: refund_id).update_all(journal_entry_id: journal_id)
  end

  def outbox_event_for(aggregate, event_type)
    @organization.outbox_events.find_by!(
      aggregate_type: aggregate.class.name,
      aggregate_id: aggregate.id,
      event_type:
    )
  end

  def create_operator(email_prefix)
    User.create!(
      email_address: "#{email_prefix}-#{SecureRandom.hex(4)}@example.com",
      password: "strong-password-123",
      role: "admin"
    )
  end

  def assert_database_constraint_violation
    connection = ActiveRecord::Base.connection
    connection.execute("SAVEPOINT database_invariant_test")

    assert_raises(ActiveRecord::StatementInvalid) do
      yield
      connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    end
  ensure
    connection.execute("ROLLBACK TO SAVEPOINT database_invariant_test")
    connection.execute("RELEASE SAVEPOINT database_invariant_test")
  end
end
