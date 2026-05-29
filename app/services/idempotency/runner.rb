module Idempotency
  class Runner
    def self.call(...)
      new(...).call
    end

    def initialize(organization:, key:, request_method:, request_path:, request_hash:)
      @organization = organization
      @key = key
      @request_method = request_method
      @request_path = request_path
      @request_hash = request_hash
    end

    def call
      return yield if key.blank?

      record, created = find_or_create_record
      unless created
        record.with_lock do
          validate_reuse!(record)
          return Idempotency::Response.new(status: record.response_status, body: record.response_body, replayed: true) if record.succeeded?

          raise Errors::IdempotencyConflict.new("A request with this idempotency key is still processing") if record.processing?

          record.update!(status: "processing", locked_at: Time.current)
        end
      end

      if created
        validate_reuse!(record)
      end

      response = yield
      record.update!(status: "succeeded", response_status: response.status, response_body: response.body)
      Idempotency::Response.new(status: response.status, body: response.body, replayed: false)
    rescue StandardError
      record&.update!(status: "failed") if record&.processing?
      raise
    end

    private

    attr_reader :organization, :key, :request_method, :request_path, :request_hash

    def find_or_create_record
      record = organization.idempotency_keys.create!(
        key:,
        request_method:,
        request_path:,
        request_hash:,
        locked_at: Time.current
      )
      [record, true]
    rescue ActiveRecord::RecordNotUnique
      [organization.idempotency_keys.find_by!(key:), false]
    end

    def validate_reuse!(record)
      return if record.request_method == request_method && record.request_path == request_path && record.request_hash == request_hash

      raise Errors::IdempotencyConflict.new
    end
  end
end
