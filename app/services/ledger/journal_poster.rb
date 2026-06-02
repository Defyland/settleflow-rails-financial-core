module Ledger
  class JournalPoster
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, event_type:, lines:, reference: nil, idempotency_key: nil, correlation_id: nil, metadata: {})
      @organization = organization
      @event_type = event_type
      @lines = lines
      @reference = reference
      @idempotency_key = idempotency_key
      @correlation_id = correlation_id
      @metadata = metadata
    end

    def call
      raise Errors::IdempotencyKeyRequired.new("Journal entries require an idempotency key") if idempotency_key.blank?
      raise Errors::ValidationError.new("Journal entries require a domain reference") if reference.blank?
      raise Errors::ValidationError.new("Journal reference belongs to another organization") if reference.respond_to?(:organization_id) && reference.organization_id != organization.id

      validate_lines!

      ActiveRecord::Base.transaction do
        journal_entry = organization.journal_entries.create!(
          event_type:,
          reference:,
          idempotency_key:,
          correlation_id:,
          occurred_at: Time.current,
          metadata:
        )

        lines.each do |line|
          journal_entry.ledger_lines.create!(
            organization:,
            ledger_account: line.fetch(:account),
            direction: line.fetch(:direction),
            amount_cents: line.fetch(:amount_cents),
            currency: line.fetch(:currency, "BRL"),
            metadata: line.fetch(:metadata, {})
          )
        end

        BalanceProjections::WriteGate.with_context("ledger_journal_poster") do
          apply_balance_projection!(journal_entry)
        end
        journal_entry
      end
    end

    private

    attr_reader :organization, :event_type, :lines, :reference, :idempotency_key, :correlation_id, :metadata

    def validate_lines!
      raise Errors::ValidationError.new("Journal entry requires at least two lines") if lines.size < 2

      lines.group_by { |line| line.fetch(:currency, "BRL") }.each_value do |currency_lines|
        debit_total = currency_lines.select { |line| line.fetch(:direction) == "debit" }.sum { |line| line.fetch(:amount_cents) }
        credit_total = currency_lines.select { |line| line.fetch(:direction) == "credit" }.sum { |line| line.fetch(:amount_cents) }
        next if debit_total == credit_total

        raise Errors::ValidationError.new(
          "Journal entry is not balanced",
          details: { debit_total_cents: debit_total, credit_total_cents: credit_total }
        )
      end

      lines.each do |line|
        account = line.fetch(:account)
        raise Errors::ValidationError.new("Ledger account belongs to another organization") if account.organization_id != organization.id
        raise Errors::ValidationError.new("Ledger account currency mismatch") if account.currency != line.fetch(:currency, "BRL")
      end
    end

    def apply_balance_projection!(journal_entry)
      journal_entry.ledger_lines.includes(ledger_account: :wallet).find_each do |line|
        wallet = line.ledger_account.wallet
        next if wallet.blank?

        projection = BalanceProjection.find_by!(
          organization:,
          wallet:,
          currency: line.currency
        )
        projection.apply_available_delta!(available_delta(line))
      end
    end

    def available_delta(line)
      if line.ledger_account.normal_credit?
        line.credit? ? line.amount_cents : -line.amount_cents
      else
        line.debit? ? line.amount_cents : -line.amount_cents
      end
    end
  end
end
