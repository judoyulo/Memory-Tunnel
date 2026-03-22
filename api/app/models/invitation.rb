class Invitation < ApplicationRecord
  belongs_to :chapter
  belongs_to :invited_by, class_name: "User"
  belongs_to :preview_memory, class_name: "Memory"

  validates :token,      presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :pending,  -> { where(accepted_at: nil) }
  scope :active,   -> { pending.where("expires_at > ?", Time.current) }
  scope :expired,  -> { where("expires_at <= ?", Time.current) }

  before_validation :generate_token, on: :create
  before_validation :set_expiry,     on: :create

  # ── Accept ───────────────────────────────────────────────────────────────────
  # Atomically marks the invitation as accepted and activates the Chapter.
  # Returns { success: true, chapter: } or { success: false, error: }.
  def accept!(accepting_user)
    return { success: false, error: :expired }        if expired?
    return { success: false, error: :already_accepted } if accepted_at.present?
    return { success: false, error: :wrong_user } \
      if chapter.member_a_id == accepting_user.id

    ActiveRecord::Base.transaction do
      rows = Invitation.where(id: id, accepted_at: nil)
                       .update_all(accepted_at: Time.current)
      raise ActiveRecord::Rollback, "already accepted" if rows.zero?

      activated = chapter.activate!(accepting_user)
      raise ActiveRecord::Rollback, "chapter activation failed" unless activated

      # Notify the sender
      NotifyInvitationAcceptedJob.perform_later(invitation_id: id)
    end

    reload
    { success: true, chapter: chapter }
  rescue => e
    { success: false, error: e.message }
  end

  def expired?
    expires_at <= Time.current
  end

  def accepted?
    accepted_at.present?
  end

  # Preview URL for the web invitation page (short-lived signed URL)
  def preview_url
    preview_memory.signed_url
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_expiry
    self.expires_at ||= ENV.fetch("INVITATION_TTL_DAYS", 7).to_i.days.from_now
  end
end
