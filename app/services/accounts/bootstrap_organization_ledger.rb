module Accounts
  class BootstrapOrganizationLedger
    SYSTEM_ACCOUNTS = {
      platform_cash: { code: "PLATFORM_CASH", name: "Platform settlement cash", account_type: "asset", normal_balance: "debit" },
      pix_clearing: { code: "PIX_CLEARING", name: "Pix clearing payable", account_type: "liability", normal_balance: "credit" }
    }.freeze

    def self.call(organization:, currency: "BRL")
      new(organization:, currency:).call
    end

    def initialize(organization:, currency:)
      @organization = organization
      @currency = currency
    end

    def call
      SYSTEM_ACCOUNTS.each_value do |account|
        organization.ledger_accounts.find_or_create_by!(code: "#{account.fetch(:code)}:#{currency}") do |ledger_account|
          ledger_account.name = account.fetch(:name)
          ledger_account.account_type = account.fetch(:account_type)
          ledger_account.normal_balance = account.fetch(:normal_balance)
          ledger_account.currency = currency
        end
      end
    end

    private

    attr_reader :organization, :currency
  end
end
