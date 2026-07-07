module Analytics
  class LedgerAnalyticsPartitions
    TABLE_NAME = "ledger_analytics_events"

    def self.ensure_month!(date)
      new(date).ensure_month!
    end

    def self.partition_name(date)
      month = date.to_date.beginning_of_month
      "#{TABLE_NAME}_y#{month.year}m#{month.month.to_s.rjust(2, '0')}"
    end

    def initialize(date)
      @date = date.to_date
    end

    def ensure_month!
      return partition_name if connection.data_source_exists?(partition_name)

      connection.execute(<<~SQL.squish)
        CREATE TABLE IF NOT EXISTS #{connection.quote_table_name(partition_name)}
        PARTITION OF #{connection.quote_table_name(TABLE_NAME)}
        FOR VALUES FROM (#{connection.quote(month_start)}) TO (#{connection.quote(next_month_start)})
      SQL

      partition_name
    end

    private

    attr_reader :date

    def connection
      ActiveRecord::Base.connection
    end

    def partition_name
      self.class.partition_name(date)
    end

    def month_start
      date.beginning_of_month
    end

    def next_month_start
      month_start.next_month
    end
  end
end
