module Database
  module ConsistencyChecks
    class ProjectionRebuild < Base
      def call
        differences = organizations.flat_map do |organization|
          BalanceProjections::Rebuilder.call(organization:, apply: false).select { |result| result.difference_cents != 0 }
        end

        check(
          name: :projection_rebuild,
          ok: differences.empty?,
          details: {
            mismatched_wallets: differences.size,
            difference_cents_sum: differences.sum(&:difference_cents)
          }
        )
      end
    end
  end
end
