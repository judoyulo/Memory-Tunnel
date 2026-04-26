class User < ApplicationRecord
  has_many :chapters_as_member_a, class_name: "Chapter", foreign_key: :member_a_id, dependent: :destroy
  has_many :chapters_as_member_b, class_name: "Chapter", foreign_key: :member_b_id, dependent: :nullify
  has_many :memories, foreign_key: :owner_id, dependent: :destroy
  has_many :invitations, foreign_key: :invited_by_id, dependent: :destroy
  has_many :daily_card_queue_entries, dependent: :destroy

  validates :phone, presence: true, uniqueness: true,
                    format: { with: /\A\+[1-9]\d{7,14}\z/, message: "must be E.164 format (e.g. +14155551234)" }
  validates :display_name, presence: true, length: { maximum: 60 }

  # ── Chapters ────────────────────────────────────────────────────────────────
  # All active chapters this user is a member of (either side)
  def chapters
    Chapter.where(status: :active)
           .where("member_a_id = ? OR member_b_id = ?", id, id)
  end

  # The other member in a given chapter
  def partner_in(chapter)
    chapter.member_a_id == id ? chapter.member_b : chapter.member_a
  end

  # ── OTP ─────────────────────────────────────────────────────────────────────
  # Generates a 6-digit OTP, stores bcrypt digest, returns the plaintext code
  # so the caller can send it via Twilio.
  def generate_otp!(override_code: nil)
    code = override_code || SecureRandom.random_number(10**6).to_s.rjust(6, "0")
    update!(
      otp_code: ::BCrypt::Password.create(code),
      otp_expires_at: ENV.fetch("OTP_EXPIRY_MINUTES", 10).to_i.minutes.from_now
    )
    code
  end

  def verify_otp!(code)
    return false if otp_expires_at.nil? || otp_expires_at < Time.current
    return false unless ::BCrypt::Password.new(otp_code) == code

    # Consume the OTP so it can't be replayed
    update!(otp_code: nil, otp_expires_at: nil)
    true
  end

  # ── Push notifications ───────────────────────────────────────────────────────
  def push_enabled?
    push_token.present?
  end
end
