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
  validates :subject_id, numericality: { only_integer: true, greater_than: 0 }
  validate :approver_must_be_different
  validate :state_has_expected_evidence
  before_update :prevent_terminal_mutation
  before_destroy :prevent_deletion

  def subject
    subject_type.constantize.find(subject_id)
  end

  private

  def state_has_expected_evidence
    if pending?
      errors.add(:approved_by_id, "must be blank while pending") if approved_by_id.present?
      errors.add(:approved_at, "must be blank while pending") if approved_at.present?
    elsif approved? || rejected?
      errors.add(:approved_by_id, "must be present for terminal decisions") if approved_by_id.blank?
      errors.add(:approved_at, "must be present for terminal decisions") if approved_at.blank?
    end
  end

  def approver_must_be_different
    return if approved_by_id.blank? || requested_by_id.blank? || approved_by_id != requested_by_id

    errors.add(:approved_by_id, "must be different from requested_by_id")
  end

  def prevent_terminal_mutation
    return unless status_in_database.in?(%w[approved rejected])

    errors.add(:base, "terminal operator approvals are immutable governance evidence")
    throw :abort
  end

  def prevent_deletion
    errors.add(:base, "operator approvals are governance evidence")
    throw :abort
  end
end
