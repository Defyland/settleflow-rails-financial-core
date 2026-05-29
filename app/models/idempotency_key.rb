class IdempotencyKey < ApplicationRecord
  belongs_to :organization

  enum :status, { processing: "processing", succeeded: "succeeded", failed: "failed" }

  validates :key, :request_method, :request_path, :request_hash, presence: true
  validates :key, uniqueness: { scope: :organization_id }
end
