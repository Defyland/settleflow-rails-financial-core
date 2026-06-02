class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { viewer: "viewer", operator: "operator", admin: "admin" }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :role, presence: true
  validates :email_address, presence: true, uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 12 }, allow_nil: true

  def can_operate?
    operator? || admin?
  end
end
