module Ops
  class CapabilityPolicy
    CAPABILITIES = {
      accept_med_case: %w[admin],
      reject_med_case: %w[admin],
      reject_pix_payment: %w[operator admin],
      retry_outbox_event: %w[operator admin],
      reverse_pix_payment: %w[admin],
      settle_pix_payment: %w[admin]
    }.freeze

    def self.allowed?(user, capability)
      CAPABILITIES.fetch(capability).include?(user&.role)
    end
  end
end
