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

  test "database rejects journal entries without command identity" do
    assert_raises(ActiveRecord::StatementInvalid) do
      JournalEntry.insert!({
        organization_id: @organization.id,
        event_type: "raw.missing_idempotency",
        occurred_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      })
    end
  end

  test "database rejects direct unbalanced journal inserts" do
    destination_wallet = create_wallet(organization: @organization)
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction do
        journal_id = JournalEntry.insert!({
          organization_id: @organization.id,
          event_type: "raw.unbalanced",
          idempotency_key: "raw-unbalanced",
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
        ActiveRecord::Base.connection.execute(
          "SET CONSTRAINTS journal_entry_balanced_after_journal_insert, journal_entry_balanced_after_line_insert IMMEDIATE"
        )
      end
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

  test "database rejects direct outbox evidence tampering and deletion" do
    event = OutboxEvents::Emit.call(
      organization: @organization,
      aggregate: @wallet,
      event_type: "wallet.test_event",
      payload: { wallet_id: @wallet.public_id, amount_cents: 10 },
      correlation_id: "db-invariant-outbox",
      idempotency_key: "db-invariant-outbox"
    )
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
  end

  test "database rejects malformed outbox payload hashes" do
    event = OutboxEvents::Emit.call(
      organization: @organization,
      aggregate: @wallet,
      event_type: "wallet.bad_hash",
      payload: { wallet_id: @wallet.public_id }
    )

    assert_database_constraint_violation { event.update_columns(payload_sha256: "not-a-sha") }
    assert_database_constraint_violation { event.update_columns(payload_sha256: "b" * 64) }
  end

  test "database rejects direct processed event evidence tampering" do
    event = OutboxEvents::Emit.call(
      organization: @organization,
      aggregate: @wallet,
      event_type: "wallet.processed_event_test",
      payload: { wallet_id: @wallet.public_id }
    )
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
