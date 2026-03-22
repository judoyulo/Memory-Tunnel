class Chapter < ApplicationRecord
  belongs_to :member_a, class_name: "User"
  belongs_to :member_b, class_name: "User", optional: true  # NULL until invitation accepted
  has_many   :memories, dependent: :destroy
  has_many   :invitations, dependent: :destroy
  has_many   :daily_card_queue_entries, dependent: :destroy

  enum :status, { pending: "pending", active: "active", archived: "archived" }

  validates :member_a, presence: true
  validates :status, presence: true

  # pending state requires invited_phone; active state requires member_b
  validates :invited_phone, presence: true, if: -> { pending? && member_b.nil? }
  validates :member_b, presence: true, if: :active?

  # ── Scopes ───────────────────────────────────────────────────────────────────
  scope :for_user, ->(user) {
    where("member_a_id = ? OR member_b_id = ?", user.id, user.id)
  }

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Returns memories visible to the requesting user from the other member's side
  #
  # Visibility rules:
  #   this_item — only memories explicitly sent in an invitation (tracked via preview_memory_id)
  #               OR any memory the owner subsequently marked as this_item AND shared via an invite
  #   all       — all memories the owner has ever added to this chapter
  #
  # In practice for the bilateral view: we show ALL of the requesting user's own memories,
  # plus only the memories from the other member that match their current visibility setting.
  def memories_visible_to(user)
    other = other_member(user)
    return Memory.none unless other

    own_memories    = memories.where(owner: user)
    their_setting   = memories.where(owner: other).pick(:visibility)

    their_memories = case their_setting
                     when "all"       then memories.where(owner: other)
                     when "this_item" then memories.where(owner: other, visibility: "this_item")
                     else                  Memory.none
                     end

    Memory.where(id: own_memories).or(Memory.where(id: their_memories))
          .order(Arel.sql("COALESCE(taken_at, created_at) DESC"))
  end

  def other_member(user)
    member_a_id == user.id ? member_b : member_a
  end

  # Activate the chapter when the invited user accepts
  # Atomic: uses RETURNING to prevent double-activation race
  def activate!(new_member)
    updated = self.class
                  .where(id: id, status: "pending")
                  .update_all(
                    member_b_id: new_member.id,
                    invited_phone: nil,
                    status: "active",
                    last_memory_at: Time.current,
                    updated_at: Time.current
                  )
    updated == 1
  end

  def touch_last_memory!
    update_column(:last_memory_at, Time.current)
  end

  def decayed?(threshold_days = nil)
    threshold_days ||= ENV.fetch("DECAY_THRESHOLD_DAYS", 90).to_i
    return false unless active?
    return true  if last_memory_at.nil?

    last_memory_at < threshold_days.days.ago
  end
end
