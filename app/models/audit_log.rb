class AuditLog < ApplicationRecord
  belongs_to :organization, optional: true

  validates :actor_type, :action, :subject_type, presence: true
end
