module Database
  module ConsistencyChecks
    class JournalBalance < Base
      def call
        rows = connection.exec_query(<<~SQL.squish)
          SELECT journal_entry_id, currency
          FROM ledger_lines
          GROUP BY journal_entry_id, currency
          HAVING
            COUNT(*) < 2 OR
            SUM(CASE WHEN direction = 'debit' THEN amount_cents ELSE 0 END) <>
            SUM(CASE WHEN direction = 'credit' THEN amount_cents ELSE 0 END)
        SQL

        check(
          name: :journal_balance,
          ok: rows.empty?,
          details: { unbalanced_journal_currency_pairs: rows.count }
        )
      end
    end
  end
end
