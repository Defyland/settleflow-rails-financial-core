class ApiCredential < ApplicationRecord
  RAW_KEY_PREFIX = "sfk".freeze
  DEFAULT_SCOPES = %w[v1:read v1:write].freeze

  belongs_to :organization

  validates :name, :key_prefix, :key_digest, presence: true
  validates :key_prefix, :key_digest, uniqueness: true
  validate :scopes_must_be_strings

  def self.issue!(organization:, name:, scopes: DEFAULT_SCOPES, expires_at: nil)
    key_prefix = SecureRandom.hex(6)
    raw_key = "#{RAW_KEY_PREFIX}_#{key_prefix}_#{SecureRandom.base58(32)}"
    credential = organization.api_credentials.create!(
      name:,
      key_prefix:,
      key_digest: digest(raw_key),
      scopes: scopes.map(&:to_s).uniq.sort,
      expires_at:
    )
    [ credential, raw_key ]
  end

  def self.authenticate(raw_key)
    key_prefix = raw_key.to_s.split("_", 3).second
    return if key_prefix.blank?

    credential = find_by(key_prefix:)
    return if credential.blank?
    return unless ActiveSupport::SecurityUtils.secure_compare(credential.key_digest, digest(raw_key))
    return unless credential.usable?

    credential.touch(:last_used_at)
    credential
  end

  def self.digest(raw_key)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_key.to_s)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def usable?
    revoked_at.blank? && (expires_at.blank? || expires_at.future?) && organization.active?
  end

  def allows?(scope)
    scopes.include?(scope.to_s)
  end

  private

  def scopes_must_be_strings
    return if scopes.is_a?(Array) && scopes.all? { |scope| scope.is_a?(String) && scope.present? }

    errors.add(:scopes, "must be a non-empty string array")
  end
end
