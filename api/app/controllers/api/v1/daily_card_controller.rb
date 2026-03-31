module Api
  module V1
    class DailyCardController < ApplicationController
      # GET /api/v1/daily_card
      # Returns today's card for the current user, or 204 if none is queued.
      # Marks the entry as delivered on first fetch.
      def show
        entry = DailyCardQueueEntry
                  .includes(chapter: %i[member_a member_b])
                  .where(user: current_user, scheduled_for: Date.current)
                  .where(delivered_at: nil)
                  .order(:priority)
                  .first

        return head :no_content unless entry

        entry.update_column(:delivered_at, Time.current)

        render json: daily_card_json(entry)
      end

      # POST /api/v1/daily_card/birthday_signal
      # Body: { chapter_id: "..." }
      # Called by iOS when on-device Contacts detection finds an upcoming birthday.
      # No birthday date is transmitted — the server just queues a birthday card.
      # Idempotent: no-ops if a birthday card is already queued for today.
      def birthday_signal
        chapter = Chapter.where(status: "active")
                         .for_user(current_user)
                         .find(params.require(:chapter_id))

        already_queued = DailyCardQueueEntry
                           .where(user: current_user, chapter: chapter,
                                  scheduled_for: Date.current, trigger_type: "birthday")
                           .exists?

        unless already_queued
          DailyCardQueueEntry.create!(
            user:          current_user,
            chapter:       chapter,
            trigger_type:  "birthday",
            scheduled_for: Date.current,
            priority:      1   # birthday cards surface above decay cards (priority: 2)
          )
        end

        head :ok
      rescue ActiveRecord::RecordNotUnique
        # Another card was already queued today (unique index: user_id + scheduled_for).
        # The signal is idempotent — treat the constraint as success.
        head :ok
      end

      # POST /api/v1/daily_card/open
      # Records when the user tapped the card open. Used for engagement analytics.
      def open
        entry = DailyCardQueueEntry
                  .where(user: current_user, scheduled_for: Date.current)
                  .where.not(delivered_at: nil)
                  .first

        entry&.update_column(:opened_at, Time.current) if entry&.opened_at.nil?
        head :ok
      end

      private

      def daily_card_json(entry)
        chapter = entry.chapter
        partner = chapter.other_member(current_user)

        # Return a few recent shared memories for the card UI to display
        memories = chapter.memories_visible_to(current_user).limit(6).map do |m|
          {
            id:         m.id,
            media_url:  m.signed_url,
            media_type: m.media_type,
            caption:    m.caption,
            taken_at:   m.taken_at,
            owner_id:   m.owner_id
          }
        end

        {
          id:           entry.id,
          trigger_type: entry.trigger_type,
          scheduled_for: entry.scheduled_for,
          chapter: {
            id:             chapter.id,
            name:           chapter.name,
            last_memory_at: chapter.last_memory_at,
            partner: {
              id:           partner&.id,
              display_name: partner&.display_name,
              avatar_url:   partner&.avatar_url
            }
          },
          memories: memories
        }
      end
    end
  end
end
