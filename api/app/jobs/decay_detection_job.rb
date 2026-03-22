# Runs nightly (via GoodJob cron) to detect chapters that have gone quiet.
# For each decayed chapter, schedules a decay card in both members' daily queues
# unless one is already queued for today or the next N days.
#
# "Decayed" = active chapter with last_memory_at older than DECAY_THRESHOLD_DAYS (default 90).
class DecayDetectionJob < ApplicationJob
  queue_as :low

  LOOKAHEAD_DAYS = 3   # don't reschedule if a decay card is already within this window

  def perform
    threshold = ENV.fetch("DECAY_THRESHOLD_DAYS", 90).to_i.days.ago

    Chapter.active
           .where("last_memory_at < ? OR last_memory_at IS NULL", threshold)
           .includes(:member_a, :member_b)
           .find_each do |chapter|
      schedule_for_member(chapter, chapter.member_a)
      schedule_for_member(chapter, chapter.member_b) if chapter.member_b
    end
  end

  private

  def schedule_for_member(chapter, user)
    return unless user

    # Skip if a decay card for this chapter is already queued in the near window
    already_queued = DailyCardQueueEntry.where(
      user:         user,
      chapter:      chapter,
      trigger_type: "decay",
      delivered_at: nil
    ).where(scheduled_for: Date.today..LOOKAHEAD_DAYS.days.from_now.to_date).exists?

    return if already_queued

    DailyCardQueueEntry.schedule!(
      user:           user,
      chapter:        chapter,
      trigger_type:   "decay",
      preferred_date: Date.today
    )
  rescue => e
    Rails.logger.error("[DecayDetectionJob] Failed for user=#{user.id} " \
                       "chapter=#{chapter.id}: #{e.message}")
  end
end
