module Reconciliation
  class RowsBuilder
    StatementEntry = Data.define(:external_id, :amount_cents, :currency, :occurred_on, :metadata)
    LedgerMatch = Data.define(:external_id, :amount_cents, :journal_entry_id, :journal_entry_ids, :occurred_on)
    MISSING = Object.new.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(run:, snapshot:, statement_entries:, currency:)
      @run = run
      @organization = run.organization
      @snapshot = snapshot
      @statement_entries = statement_entries || []
      @currency = currency
    end

    def call
      rows = [
        create_cash_balance_row,
        create_projection_balance_row
      ]

      return rows if normalized_statement_entries.empty?

      rows + create_provider_statement_rows + create_missing_provider_rows
    end

    private

    attr_reader :run, :organization, :snapshot, :statement_entries, :currency

    def create_cash_balance_row
      create_row!(
        row_type: "cash_balance",
        status: run.discrepancy_cents.zero? ? "matched" : "discrepant",
        external_id: "cash_balance:#{run.provider}:#{run.statement_date.iso8601}",
        occurred_on: run.statement_date,
        provider_amount_cents: run.provider_balance_cents,
        ledger_amount_cents: run.ledger_balance_cents,
        metadata: {
          provider: run.provider,
          statement_date: run.statement_date.iso8601
        }
      )
    end

    def create_projection_balance_row
      projection_difference = snapshot.fetch(:projection_difference_cents).to_i
      create_row!(
        row_type: "projection_balance",
        status: projection_difference.zero? ? "matched" : "discrepant",
        external_id: "projection_balance:#{currency}",
        occurred_on: run.statement_date,
        provider_amount_cents: snapshot.fetch(:projection_available_cents).to_i,
        ledger_amount_cents: snapshot.fetch(:wallet_liability_cents).to_i,
        metadata: {
          wallet_count: snapshot.fetch(:wallet_count)
        }
      )
    end

    def create_provider_statement_rows
      normalized_statement_entries.map do |entry|
        ledger_match = ledger_matches_by_external_id[entry.external_id]
        ledger_amount = ledger_match&.amount_cents.to_i
        status = statement_status(ledger_match, provider_amount: entry.amount_cents, ledger_amount:)

        create_row!(
          row_type: "provider_statement_entry",
          status:,
          external_id: entry.external_id,
          occurred_on: entry.occurred_on,
          provider_amount_cents: entry.amount_cents,
          ledger_amount_cents: ledger_amount,
          journal_entry_id: ledger_match&.journal_entry_id,
          metadata: entry.metadata.merge(
            ledger_journal_entry_ids: ledger_match&.journal_entry_ids || []
          )
        )
      end
    end

    def create_missing_provider_rows
      matched_external_ids = normalized_statement_entries.map(&:external_id).to_set
      ledger_matches_by_external_id.values.filter_map do |ledger_match|
        next if matched_external_ids.include?(ledger_match.external_id)

        create_row!(
          row_type: "ledger_statement_entry",
          status: "missing_in_provider",
          external_id: ledger_match.external_id,
          occurred_on: ledger_match.occurred_on || run.statement_date,
          provider_amount_cents: 0,
          ledger_amount_cents: ledger_match.amount_cents,
          journal_entry_id: ledger_match.journal_entry_id,
          metadata: {
            ledger_journal_entry_ids: ledger_match.journal_entry_ids
          }
        )
      end
    end

    def statement_status(ledger_match, provider_amount:, ledger_amount:)
      return "missing_in_ledger" if ledger_match.blank?
      return "matched" if provider_amount == ledger_amount

      "discrepant"
    end

    def create_row!(row_type:, status:, external_id:, occurred_on:, provider_amount_cents:, ledger_amount_cents:, metadata:, journal_entry_id: nil)
      run.reconciliation_rows.create!(
        organization:,
        journal_entry_id:,
        row_type:,
        status:,
        external_id:,
        occurred_on:,
        provider_amount_cents:,
        ledger_amount_cents:,
        difference_cents: provider_amount_cents - ledger_amount_cents,
        currency:,
        metadata:
      )
    end

    def normalized_statement_entries
      @normalized_statement_entries ||= statement_entries
        .map { |entry| normalize_statement_entry(entry) }
        .group_by(&:external_id)
        .map { |_external_id, entries| merge_statement_entries(entries) }
    end

    def normalize_statement_entry(entry)
      attributes = statement_entry_attributes(entry)
      external_id = fetch_statement_attribute(attributes, :external_id, error: "Statement entry external_id is required").to_s
      raise Errors::ValidationError.new("Statement entry external_id is required") if external_id.blank?

      entry_currency = fetch_statement_attribute(attributes, :currency, default: currency).to_s
      raise Errors::ValidationError.new("Statement entry currency mismatch") if entry_currency != currency

      occurred_on = fetch_statement_attribute(attributes, :occurred_on, default: run.statement_date)
      metadata = fetch_statement_attribute(attributes, :metadata, default: {}) || {}
      metadata = metadata.to_unsafe_h if metadata.respond_to?(:to_unsafe_h)

      StatementEntry.new(
        external_id:,
        amount_cents: cast_amount_cents(
          fetch_statement_attribute(attributes, :amount_cents, error: "Statement entry amount_cents is required")
        ),
        currency: entry_currency,
        occurred_on: cast_date(occurred_on),
        metadata:
      )
    end

    def merge_statement_entries(entries)
      first_entry = entries.first
      StatementEntry.new(
        external_id: first_entry.external_id,
        amount_cents: entries.sum(&:amount_cents),
        currency: first_entry.currency,
        occurred_on: entries.map(&:occurred_on).min,
        metadata: first_entry.metadata.merge(provider_row_count: entries.size)
      )
    end

    def cast_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Errors::ValidationError.new("Statement entry occurred_on must be ISO-8601")
    end

    def statement_entry_attributes(entry)
      attributes = if entry.respond_to?(:to_unsafe_h)
        entry.to_unsafe_h
      elsif entry.respond_to?(:to_h)
        entry.to_h
      end
      return attributes if attributes.respond_to?(:key?)

      raise Errors::ValidationError.new("Statement entry must be an object")
    end

    def cast_amount_cents(value)
      Integer(value, exception: true)
    rescue ArgumentError, TypeError
      raise Errors::ValidationError.new("Statement entry amount_cents must be an integer")
    end

    def fetch_statement_attribute(attributes, key, default: MISSING, error: nil)
      string_key = key.to_s
      return attributes[string_key] if attributes.key?(string_key)
      return attributes[key] if attributes.key?(key)
      return default unless default.equal?(MISSING)

      raise Errors::ValidationError.new(error || "Statement entry #{string_key} is required")
    end

    def ledger_matches_by_external_id
      @ledger_matches_by_external_id ||= begin
        matches = {}
        platform_cash_lines.find_each do |line|
          external_id = line.journal_entry.metadata["external_id"].to_s
          next if external_id.blank?

          current = matches[external_id]
          signed_amount = signed_amount_cents(line)
          matches[external_id] = LedgerMatch.new(
            external_id:,
            amount_cents: current&.amount_cents.to_i + signed_amount,
            journal_entry_id: current&.journal_entry_id || line.journal_entry_id,
            journal_entry_ids: Array(current&.journal_entry_ids) | [ line.journal_entry_id ],
            occurred_on: [ current&.occurred_on, line.journal_entry.occurred_at.to_date ].compact.min
          )
        end
        matches
      end
    end

    def platform_cash_lines
      LedgerLine
        .includes(:journal_entry, :ledger_account)
        .where(organization:, ledger_account: platform_cash_account, currency:)
        .where(journal_entries: { status: "posted", occurred_at: run.statement_date.all_day })
        .references(:journal_entries)
    end

    def platform_cash_account
      @platform_cash_account ||= Ledger::AccountLocator.platform_cash(organization:, currency:)
    end

    def signed_amount_cents(line)
      if line.ledger_account.normal_debit?
        line.debit? ? line.amount_cents : -line.amount_cents
      else
        line.credit? ? line.amount_cents : -line.amount_cents
      end
    end
  end
end
