class DailyCardQueueEntry < ApplicationRecord
  belongs_to :user
  belongs_to :chapter

  PRIORITIES = { birthday: 1, decay: 2, manual: 3 }.freeze

  enum :trigger_type, { birthday: "birthday", decay: "decay", manual: "manual" }

  validates :user, :chapter, :trigger_type, :priority, :scheduled_for, presence: true

  scope :pending_delivery, -> { where(delivered_at: nil).order(:priority, :scheduled_for) }
  scope :for_date,         ->(date) { where(scheduled_for: date) }
  scope :delivered,        -> { where.not(delivered_at: nil) }

  # ── Scheduling ───────────────────────────────────────────────────────────────
  # Enqueue a card for a user, skipping days already taken.
  # Returns the entry or nil if the chapter already has a card in the near future.
  def self.schedule!(user:, chapter:, trigger_type:, preferred_date: Date.current)
    priority = PRIORITIES.fetch(trigger_type.to_sym)

    # Find the next available date on or after preferred_date
    taken_dates = where(user: user).pluck(:scheduled_for).to_set
    scheduled_date = preferred_date
    scheduled_date += 1.day while taken_dates.include?(scheduled_date)

    create!(
      user: user,
      chapter: chapter,
      trigger_type: trigger_type,
      priority: priority,
      scheduled_for: scheduled_date
    )
  rescue ActiveRecord::RecordNotUnique
    nil  # Already has a card on that date — skip silently
  end

  # Today's card for a user (the one to show / push)
  def self.todays_card(user)
    where(user: user)
      .for_date(Date.current)
      .order(:priority)
      .first
  end

  def mark_delivered!
    update!(delivered_at: Time.current)
  end

  def mark_opened!
    update!(opened_at: Time.current)
  end
end
