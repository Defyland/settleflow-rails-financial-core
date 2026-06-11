module Database
  module ConsistencyChecks
    class AuditChains < Base
      def call
        [ audit_hash_chain_check, audit_anchor_chain_check ]
      end

      private

      def audit_hash_chain_check
        check(
          name: :audit_hash_chain,
          ok: AuditLog.hash_chain_intact?,
          details: {
            hash_mismatches: AuditLog.hash_mismatches.count,
            broken_links: AuditLog.broken_chain_links.count,
            invalid_genesis_links: AuditLog.invalid_genesis_links.count
          }
        )
      end

      def audit_anchor_chain_check
        check(
          name: :audit_anchor_chain,
          ok: AuditLogAnchor.anchor_chain_intact?,
          details: {
            anchor_hash_mismatches: AuditLogAnchor.hash_mismatches.count,
            broken_anchor_links: AuditLogAnchor.broken_anchor_links.count,
            latest_anchor_sequence: AuditLogAnchor.maximum(:chain_sequence),
            latest_audit_sequence: AuditLog.maximum(:chain_sequence),
            latest_anchor_covers_current_audit_tail: AuditLogAnchor.latest_covers_current_audit_tail?
          }
        )
      end
    end
  end
end
