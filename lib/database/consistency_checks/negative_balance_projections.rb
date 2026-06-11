module Database
  module ConsistencyChecks
    class NegativeBalanceProjections < Base
      def call
        count = BalanceProjection.where("available_cents < 0 OR pending_cents < 0 OR blocked_cents < 0").count

        check(
          name: :negative_balance_projections,
          ok: count.zero?,
          details: { negative_projection_rows: count }
        )
      end
    end
  end
end
