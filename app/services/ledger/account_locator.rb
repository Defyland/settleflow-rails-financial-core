module Ledger
  class AccountLocator
    def self.platform_cash(organization:, currency:)
      organization.ledger_accounts.find_by!(code: "PLATFORM_CASH:#{currency}")
    end

    def self.pix_clearing(organization:, currency:)
      organization.ledger_accounts.find_by!(code: "PIX_CLEARING:#{currency}")
    end

    def self.payout_clearing(organization:, currency:)
      organization.ledger_accounts.find_by!(code: "PAYOUT_CLEARING:#{currency}")
    end
  end
end
