module BalanceProjections
  class Rebuilder < ApplicationService
    Result = Data.define(:wallet_id, :currency, :current_available_cents, :rebuilt_available_cents, :difference_cents)
    def initialize(organization:, wallet: nil, currency: "BRL", apply: false)
      @organization = organization
      @wallet = wallet
      @currency = currency
      @apply = apply
    end

    def call
      scope = wallet.present? ? organization.wallets.where(id: wallet.id) : organization.wallets
      scope.includes(:balance_projection, :ledger_accounts).where(currency:).map do |record|
        rebuild_wallet(record)
      end
    end

    private

    attr_reader :organization, :wallet, :currency, :apply

    def rebuild_wallet(record)
      return rebuild_wallet_with_apply(record) if apply

      projection = record.balance_projection
      rebuilt_available_cents = record.liability_account.balance_cents
      difference_cents = projection.available_cents - rebuilt_available_cents

      Result.new(
        wallet_id: record.public_id,
        currency:,
        current_available_cents: projection.available_cents,
        rebuilt_available_cents:,
        difference_cents:
      )
    end

    def rebuild_wallet_with_apply(record)
      projection = record.balance_projection

      ActiveRecord::Base.transaction do
        projection.lock!
        rebuilt_available_cents = record.liability_account.balance_cents
        current_available_cents = projection.available_cents
        difference_cents = current_available_cents - rebuilt_available_cents

        if difference_cents != 0
          BalanceProjections::WriteGate.with_context("balance_projection_rebuilder") do
            projection.update!(available_cents: rebuilt_available_cents)
          end
        end

        Result.new(
          wallet_id: record.public_id,
          currency:,
          current_available_cents:,
          rebuilt_available_cents:,
          difference_cents:
        )
      end
    end
  end
end
