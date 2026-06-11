module FinancialLifecycle
  class StatusGuard
    def self.ensure_wallet_active!(wallet, role:)
      return if wallet.active?

      raise Errors::ValidationError.new(
        "#{role_label(role)} wallet must be active",
        details: {
          wallet_id: wallet.public_id,
          wallet_status: wallet.status,
          role: role.to_s
        }
      )
    end

    def self.ensure_customer_active!(customer, role:)
      return if customer.active?

      raise Errors::ValidationError.new(
        "#{role_label(role)} customer must be active",
        details: {
          customer_id: customer.public_id,
          customer_status: customer.status,
          role: role.to_s
        }
      )
    end

    def self.role_label(role)
      role.to_s.tr("_", " ").capitalize
    end
    private_class_method :role_label
  end
end
