module Payouts
  class Settle < ApplicationService
    def initialize(organization:, payout:, correlation_id: nil, force: false, operator: nil, reason: nil)
      @organization = organization
      @payout = payout
      @correlation_id = correlation_id
      @force = force
      @operator = operator
      @reason = reason.presence || "early_payout_settlement"
    end

    def call
      raise Errors::ValidationError.new("Payout belongs to another organization") if payout.organization_id != organization.id

      payout.reload
      if early_settlement?
        require_early_settlement_request!

        return Ops::MakerChecker.call(
          action: FinancialContracts::Actions::PAYOUT_SETTLE_EARLY,
          subject: payout,
          operator:,
          reason:,
          correlation_id:
        ) do |approval|
          settle!(operator_approval: approval)
        end
      end

      settle!(operator_approval: nil)
    end

    private

    attr_reader :organization, :payout, :correlation_id, :force, :operator, :reason

    def early_settlement?
      payout.scheduled? && payout.settlement_due_on > Date.current
    end

    def require_early_settlement_request!
      raise Errors::ValidationError.new("Payout settlement date has not arrived", details: { settlement_due_on: payout.settlement_due_on.iso8601 }) unless force
      raise Errors::AuthorizationError.new("Early payout settlement requires ops maker-checker approval") if operator.blank?
    end

    def ensure_settlement_allowed!(operator_approval:)
      raise Errors::ValidationError.new("Payout must be scheduled before settlement", details: { status: payout.status }) unless payout.scheduled?
      raise Errors::AuthorizationError.new("Early payout settlement requires ops maker-checker approval") if early_settlement? && operator_approval.blank?
    end

    def settle!(operator_approval:)
      ActiveRecord::Base.transaction do
        payout.lock!
        ensure_settlement_allowed!(operator_approval:)

        Accounts::BootstrapOrganizationLedger.call(organization:, currency: payout.currency)
        settlement_key = FinancialContracts.payout_settlement_key(payout)
        journal_entry = Ledger::JournalPoster.call(
          organization:,
          event_type: FinancialContracts::Events::PAYOUT_SETTLED,
          reference: payout,
          idempotency_key: settlement_key,
          correlation_id:,
          metadata: { external_id: payout.external_id, settlement_due_on: payout.settlement_due_on.iso8601 },
          lines: [
            { account: Ledger::AccountLocator.payout_clearing(organization:, currency: payout.currency), direction: "debit", amount_cents: payout.amount_cents, currency: payout.currency },
            { account: Ledger::AccountLocator.platform_cash(organization:, currency: payout.currency), direction: "credit", amount_cents: payout.amount_cents, currency: payout.currency }
          ]
        )
        payout.update!(
          status: "settled",
          settlement_journal_entry: journal_entry,
          settled_at: Time.current,
          operator_approval:
        )
        OutboxEvents::Emit.call(
          organization:,
          aggregate: payout,
          event_type: FinancialContracts::Events::PAYOUT_SETTLED,
          correlation_id:,
          idempotency_key: settlement_key,
          payload: {
            payout_id: payout.public_id,
            wallet_id: payout.wallet.public_id,
            amount_cents: payout.amount_cents,
            currency: payout.currency,
            settlement_due_on: payout.settlement_due_on.iso8601
          }
        )
        payout
      end
    end
  end
end
