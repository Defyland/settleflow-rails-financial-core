class OperatorApproval < ApplicationRecord
  belongs_to :organization
  belongs_to :requested_by, class_name: "User"
  belongs_to :approved_by, class_name: "User", optional: true

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }

  validates :action, :subject_type, :subject_id, :status, presence: true
  validates :action, uniqueness: {
    scope: [ :subject_type, :subject_id ],
    conditions: -> { where(status: "pending") },
    message: "already has a pending approval for this subject"
  }
  validate :approver_must_be_different

  def subject
    subject_type.constantize.find(subject_id)
  end

  private

  def approver_must_be_different
    return if approved_by_id.blank? || requested_by_id.blank? || approved_by_id != requested_by_id

    errors.add(:approved_by_id, "must be different from requested_by_id")
  end
end
