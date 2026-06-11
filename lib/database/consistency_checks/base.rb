module Database
  module ConsistencyChecks
    class Base
      def self.call(...)
        new(...).call
      end

      def initialize(organizations: Organization.all)
        @organizations = organizations
      end

      private

      attr_reader :organizations

      def check(name:, ok:, details:)
        Database::ConsistencyCheck.new(name:, ok:, details:)
      end

      def connection
        ActiveRecord::Base.connection
      end

      def catalog_value(sql)
        ActiveRecord::Type::Boolean.new.cast(connection.select_value(sql))
      end

      def sanitize_sql_array(statement)
        ActiveRecord::Base.send(:sanitize_sql_array, statement)
      end
    end
  end
end
