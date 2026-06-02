class IdempotencyKey < ApplicationRecord
  belongs_to :organization

  enum :status, { processing: "processing", succeeded: "succeeded", failed: "failed" }

  validates :key, :request_method, :request_path, :request_hash, presence: true
  validates :request_hash, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :response_status, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }, allow_nil: true
  validates :key, uniqueness: { scope: :organization_id }
  validate :state_has_expected_response_evidence

  private

  def state_has_expected_response_evidence
    if processing?
      errors.add(:locked_at, "must be present while processing") if locked_at.blank?
      errors.add(:response_status, "must be blank while processing") if response_status.present?
    elsif succeeded?
      errors.add(:response_status, "must be present after success") if response_status.blank?
    elsif failed? && response_status.present?
      errors.add(:response_status, "must be blank after failure")
    end
  end
end
