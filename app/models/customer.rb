class Customer < ApplicationRecord
  belongs_to :organization
  has_many :wallets, dependent: :restrict_with_exception

  enum :status, { active: "active", blocked: "blocked", closed: "closed" }

  validates :external_id, :legal_name, :document_kind, :document_number, presence: true
  validates :external_id, uniqueness: { scope: :organization_id }
  validates :document_number, uniqueness: { scope: :organization_id }
  validates :document_kind, inclusion: { in: %w[cpf cnpj tax_id] }
end
