module BalanceProjections
  class WriteGate
    ALLOWED_CONTEXTS = %w[
      ledger_journal_poster
      balance_projection_rebuilder
    ].freeze

    def self.with_context(context)
      new(context).with_context { yield }
    end

    def initialize(context)
      @context = context.to_s
    end

    def with_context
      raise ArgumentError, "unsupported balance projection write context" unless context.in?(ALLOWED_CONTEXTS)

      connection = ActiveRecord::Base.connection
      raise "balance projection write gate requires an open transaction" unless connection.transaction_open?

      previous_context = current_context(connection).presence || "none"
      connection.execute("SELECT set_config('settleflow.balance_projection_write_context', #{connection.quote(context)}, true)")
      yield
    ensure
      if connection&.transaction_open?
        connection.execute("SELECT set_config('settleflow.balance_projection_write_context', #{connection.quote(previous_context)}, true)")
      end
    end

    private

    attr_reader :context

    def current_context(connection)
      connection.select_value("SELECT current_setting('settleflow.balance_projection_write_context', true)")
    end
  end
end
