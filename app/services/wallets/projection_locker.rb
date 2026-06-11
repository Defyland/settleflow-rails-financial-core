module Wallets
  class ProjectionLocker
    def self.lock!(*wallets)
      wallets.flatten.compact.uniq(&:id).sort_by(&:id).each do |wallet|
        wallet.balance_projection.lock!
      end
    end
  end
end
