module Ops
  class CapabilityPolicy
    # Every ops mutation is admin-only. Operators (User#role) are global staff
    # with no organization_id, and ops boundaries resolve records globally by
    # public_id, so any operator-writable action would be a blind cross-tenant
    # write. Reads are already admin-gated in Ops::BaseController; writes match.
    CAPABILITIES = {
      accept_med_case: %w[admin],
      reject_med_case: %w[admin],
      reject_pix_payment: %w[admin],
      retry_outbox_event: %w[admin],
      reverse_pix_payment: %w[admin],
      settle_pix_payment: %w[admin]
    }.freeze

    def self.allowed?(user, capability)
      CAPABILITIES.fetch(capability).include?(user&.role)
    end
  end
end
