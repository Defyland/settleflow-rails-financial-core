module AuditLogs
  class HashChainAnchor
    ADVISORY_LOCK_KEY = 860029002

    def self.call(...)
      new(...).call
    end

    def initialize(publisher: self.class.default_publisher)
      @publisher = publisher
    end

    def call
      raise Errors::ValidationError.new("Audit hash chain is not intact") unless AuditLog.hash_chain_intact?
      raise Errors::ValidationError.new("Audit anchor chain is not intact") unless AuditLogAnchor.anchor_chain_intact?

      anchor = nil
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_KEY})")
        audit_log = latest_audit_log
        raise Errors::ValidationError.new("Cannot anchor an empty audit log chain") if audit_log.blank?

        existing_anchor = AuditLogAnchor.find_by(chain_sequence: audit_log.chain_sequence, hash_value: audit_log.hash_value)
        anchor = existing_anchor || create_anchor!(audit_log)
      end

      publish(anchor) if publisher.present?
      anchor
    end

    private

    attr_reader :publisher

    def latest_audit_log
      AuditLog.order(chain_sequence: :desc).first
    end

    def create_anchor!(audit_log)
      previous_anchor = AuditLogAnchor.order(:id).last
      anchored_at = Time.current
      AuditLogAnchor.create!(
        organization: audit_log.organization,
        audit_log:,
        chain_sequence: audit_log.chain_sequence,
        hash_value: audit_log.hash_value,
        previous_anchor_hash: previous_anchor&.anchor_hash,
        anchor_hash: anchor_hash(
          chain_sequence: audit_log.chain_sequence,
          hash_value: audit_log.hash_value,
          previous_anchor_hash: previous_anchor&.anchor_hash,
          anchored_at:
        ),
        anchored_at:,
        metadata: { source: "audit.hash_chain_anchor" }
      )
    end

    def anchor_hash(chain_sequence:, hash_value:, previous_anchor_hash:, anchored_at:)
      quoted_time = AuditLogAnchor.connection.quote(anchored_at)
      quoted_hash = AuditLogAnchor.connection.quote(hash_value)
      quoted_previous = previous_anchor_hash.present? ? AuditLogAnchor.connection.quote(previous_anchor_hash) : "NULL"
      AuditLogAnchor.connection.select_value(<<~SQL.squish)
        SELECT encode(
          digest(
            jsonb_build_object(
              'chain_sequence', #{chain_sequence.to_i},
              'hash_value', #{quoted_hash},
              'previous_anchor_hash', #{quoted_previous},
              'hash_algorithm', 'sha256',
              'anchored_at', #{quoted_time}::timestamp
            )::text,
            'sha256'
          ),
          'hex'
        )
      SQL
    end

    def publish(anchor)
      publisher.publish(anchor.envelope)
    end

    def self.default_publisher
      return unless ENV["AUDIT_ANCHOR_WEBHOOK_URL"].present?

      Outbox::Publishers::HttpPublisher.new(
        ENV.fetch("AUDIT_ANCHOR_WEBHOOK_URL"),
        secret: ENV["AUDIT_ANCHOR_WEBHOOK_SECRET"]
      )
    end
  end
end
