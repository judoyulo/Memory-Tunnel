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

      # POST /api/v1/daily_card/open
      # Records when the user tapped the card open. Used for engagement analytics.
      def open
        entry = DailyCardQueueEntry
                  .where(user: current_user, scheduled_for: Date.current)
                  .where.not(delivered_at: nil)
                  .first

        entry&.update_column(:opened_at, Time.current)
        head :ok
      end

      private

      def daily_card_json(entry)
        chapter = entry.chapter
        partner = chapter.other_member(current_user)

        # Return a few recent shared memories for the card UI to display
        memories = chapter.memories_visible_to(current_user).limit(6).map do |m|
          {
            id:        m.id,
            media_url: m.signed_url,
            caption:   m.caption,
            taken_at:  m.taken_at,
            owner_id:  m.owner_id
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
