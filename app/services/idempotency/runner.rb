module Idempotency
  class Runner
    PROCESSING_LOCK_TIMEOUT = 10.minutes

    def self.call(**kwargs, &block)
      new(**kwargs).call(&block)
    end

    def initialize(organization:, key:, request_method:, request_path:, request_hash:)
      @organization = organization
      @key = key
      @request_method = request_method
      @request_path = request_path
      @request_hash = request_hash
    end

    def call(&block)
      raise Errors::IdempotencyKeyRequired if key.blank?

      replay = nil
      response = nil
      processing_owner = false
      ActiveRecord::Base.transaction do
        record, created = find_or_create_record
        record.lock!
        validate_reuse!(record)

        if !created && record.succeeded?
          replay = Idempotency::Response.new(status: record.response_status, body: record.response_body, replayed: true)
          next
        end

        if !created && record.processing? && !stale_processing?(record)
          raise Errors::IdempotencyConflict.new("A request with this idempotency key is still processing")
        end

        record.update!(status: "processing", locked_at: Time.current) unless created && record.processing?
        processing_owner = true
        response = block.call
        record.update!(status: "succeeded", response_status: response.status, response_body: response.body)
      end

      replay || Idempotency::Response.new(status: response.status, body: response.body, replayed: false)
    rescue StandardError
      mark_failed_if_processing if processing_owner
      raise
    end

    private

    attr_reader :organization, :key, :request_method, :request_path, :request_hash

    def find_or_create_record
      record = organization.idempotency_keys.find_or_initialize_by(key:)
      return [ record, false ] if record.persisted?

      record.assign_attributes(
        key:,
        request_method:,
        request_path:,
        request_hash:,
        locked_at: Time.current
      )
      record.save!
      [ record, true ]
    rescue ActiveRecord::RecordNotUnique
      [ organization.idempotency_keys.find_by!(key:), false ]
    end

    def stale_processing?(record)
      record.locked_at.blank? || record.locked_at < PROCESSING_LOCK_TIMEOUT.ago
    end

    def mark_failed_if_processing
      record = organization.idempotency_keys.find_by(key:)
      return unless record&.processing?
      return unless record.request_method == request_method && record.request_path == request_path && record.request_hash == request_hash

      record.update!(status: "failed")
    rescue StandardError
      nil
    end

    def validate_reuse!(record)
      return if record.request_method == request_method && record.request_path == request_path && record.request_hash == request_hash

      raise Errors::IdempotencyConflict.new
    end
  end
end
