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
    journal = post_transfer_journal(
      external_id: "journal-poster-transfer-reference",
      idempotency_key: "journal-poster-transfer",
      amount_cents: 2_500
    )

    assert journal.balanced?
    assert_equal 7_500, @source_wallet.balance_projection.reload.available_cents
    assert_equal 2_500, @destination_wallet.balance_projection.reload.available_cents
  end

  test "rejects unbalanced journal entries before persistence" do
    assert_raises(Errors::ValidationError) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "wallet.transfer.posted",
        reference: journal_reference("journal-poster-unbalanced-reference", amount_cents: 2_500),
        idempotency_key: "journal-poster-unbalanced",
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_400, currency: "BRL" }
        ]
      )
    end

    assert_empty JournalEntry.where(idempotency_key: "journal-poster-unbalanced")
  end

  test "requires command identity for every posted journal entry" do
    assert_raises(Errors::IdempotencyKeyRequired) do
      Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "wallet.transfer.posted",
        reference: journal_reference("journal-poster-missing-idempotency-reference", amount_cents: 2_500),
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
        event_type: "wallet.transfer.posted",
        idempotency_key: "journal-poster-direct-adjustment",
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents: 2_500, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents: 2_500, currency: "BRL" }
        ]
      )
    end

    assert_empty JournalEntry.where(idempotency_key: "journal-poster-direct-adjustment")
  end

  test "rejects journal entries that would overdraw a wallet projection" do
    assert_raises(Errors::InsufficientFunds) do
      post_transfer_journal(
        external_id: "journal-poster-overdraw-reference",
        idempotency_key: "journal-poster-overdraw",
        amount_cents: 12_500
      )
    end

    assert_empty JournalEntry.where(idempotency_key: "journal-poster-overdraw")
    assert_equal 10_000, @source_wallet.balance_projection.reload.available_cents
    assert_equal 0, @destination_wallet.balance_projection.reload.available_cents
  end

  test "prevents mutation and deletion of posted ledger records" do
    journal = post_transfer_journal(
      external_id: "journal-poster-immutable-reference",
      idempotency_key: "journal-poster-immutable",
      amount_cents: 2_500
    )
    line = journal.ledger_lines.first

    assert_raises(ActiveRecord::ReadOnlyRecord) { journal.update!(metadata: { corrected: true }) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { journal.destroy! }
    assert_raises(ActiveRecord::ReadOnlyRecord) { line.update!(amount_cents: 1_000) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { line.destroy! }
  end

  private

  def post_transfer_journal(external_id:, idempotency_key:, amount_cents:)
    transfer = journal_reference(external_id, amount_cents:, idempotency_key:)
    journal = nil

    ActiveRecord::Base.transaction do
      journal = Ledger::JournalPoster.call(
        organization: @organization,
        event_type: "wallet.transfer.posted",
        reference: transfer,
        idempotency_key:,
        lines: [
          { account: @source_wallet.liability_account, direction: "debit", amount_cents:, currency: "BRL" },
          { account: @destination_wallet.liability_account, direction: "credit", amount_cents:, currency: "BRL" }
        ]
      )
      transfer.update!(journal_entry: journal)
    end

    journal
  end

  def journal_reference(external_id, amount_cents:, idempotency_key: external_id)
    @organization.transfers.create!(
      source_wallet: @source_wallet,
      destination_wallet: @destination_wallet,
      external_id:,
      amount_cents:,
      currency: "BRL",
      idempotency_key:
    )
  end
end
