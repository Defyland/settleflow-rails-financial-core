require "test_helper"

class LedgerJournalPosterTest < ActiveSupport::TestCase
  setup do
    @organization = create_organization
    @source_wallet = create_wallet(organization: @organization)
    @destination_wallet = create_wallet(organization: @organization)
    fund_wallet(
      organization: @organization,
      wallet: @source_wallet,
      external_id: "initial-funding",
      amount_cents: 10_000
    )
  end

  test "posts balanced double-entry lines and updates wallet projections" do
    journal = Ledger::JournalPoster.call(
      organization: @organization,
      event_type: "test.transfer",
      reference: journal_reference("journal-poster-transfer-reference"),
      idempotency_key: "journal-poster-transfer",
      lines: [
        { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
        { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
      ]
    )

    assert journal.balanced?
    assert_equal 7_500, @source_wallet.balance_projection.reload.available_cents
    assert_equal 2_500, @destination_wallet.balance_projection.reload.available_cents
  end

  test "rejects unbalanced journal entries before persistence" do
    assert_raises(Errors::ValidationError) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "test.bad_entry",
        reference: journal_reference("journal-poster-unbalanced-reference"),
        idempotency_key: "journal-poster-unbalanced",
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_400, currency: "BRL" }
        ]
      )
    end

    assert_empty JournalEntry.where(event_type: "test.bad_entry")
  end

  test "requires command identity for every posted journal entry" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "test.missing_idempotency_key",
        reference: journal_reference("journal-poster-missing-idempotency-reference"),
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
        ]
      )
    end
  end

  test "rejects direct journal entries without a domain reference" do
    assert_raises(Errors::ValidationError) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "test.direct_adjustment",
        idempotency_key: "journal-poster-direct-adjustment",
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
        ]
      )
    end

    assert_empty JournalEntry.where(event_type: "test.direct_adjustment")
  end

  test "rejects journal entries that would overdraw a wallet projection" do
    assert_raises(Errors::InsufficientFunds) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "test.overdraw_wallet",
        reference: journal_reference("journal-poster-overdraw-reference"),
        idempotency_key: "journal-poster-overdraw",
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 12_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 12_500, currency: "BRL" }
        ]
      )
    end

    assert_empty JournalEntry.where(event_type: "test.overdraw_wallet")
    assert_equal 10_000, @source_wallet.balance_projection.reload.available_cents
    assert_equal 0, @destination_wallet.balance_projection.reload.available_cents
  end

  test "prevents mutation and deletion of posted ledger records" do
    journal = Ledger::JournalPoster.call(
      organization: @organization,
      event_type: "test.immutable_entry",
      reference: journal_reference("journal-poster-immutable-reference"),
      idempotency_key: "journal-poster-immutable",
      lines: [
        { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
        { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
      ]
    )
    line = journal.ledger_lines.first

    assert_raises(ActiveRecord::ReadOnlyRecord) { journal.update!(metadata: { corrected: true }) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { journal.destroy! }
    assert_raises(ActiveRecord::ReadOnlyRecord) { line.update!(amount_cents: 1_000) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { line.destroy! }
  end

  private

  def journal_reference(external_id)
    @organization.transfers.create!(
      source_wallet: @source_wallet,
      destination_wallet: @destination_wallet,
      external_id:,
      amount_cents: 1,
      currency: "BRL",
      idempotency_key: external_id
    )
  end
end
