module Api
  module V1
    class MemoriesController < ApplicationController
      before_action :set_chapter

      # GET /api/v1/chapters/:chapter_id/memories
      # Returns all memories visible to the current user in this chapter,
      # ordered by effective date descending.
      def index
        memories = @chapter.memories_visible_to(current_user)
        render json: memories.map { |m| memory_json(m) }
      end

      # POST /api/v1/chapters/:chapter_id/memories/presign
      # Returns a presigned S3 PUT URL so the client can upload directly to S3.
      # Client must call POST /memories (create) after upload completes.
      def presign
        result = Memory.presign_upload(
          chapter_id:   @chapter.id,
          owner_id:     current_user.id,
          content_type: params[:content_type] || "image/jpeg"
        )
        render json: result, status: :ok
      end

      # POST /api/v1/chapters/:chapter_id/memories
      # Body: { s3_key:, caption:, taken_at:, visibility: }
      # Called after the client has confirmed the S3 upload succeeded.
      def create
        media_type = params.fetch(:media_type, "photo")

        # Text and location_checkin memories don't need S3
        if %w[text location_checkin].include?(media_type)
          key = nil
        else
          key = params.require(:s3_key).to_s
          unless key.start_with?("memories/#{@chapter.id}/") && !key.include?("..")
            return render json: { error: "invalid s3_key" }, status: :unprocessable_entity
          end
        end

        memory = @chapter.memories.create!(
          owner:         current_user,
          s3_key:        key,
          caption:       params[:caption],
          taken_at:      params[:taken_at],
          visibility:    params.fetch(:visibility, "this_item"),
          media_type:    params.fetch(:media_type, "photo"),
          location_name: params[:location_name],
          latitude:      params[:latitude],
          longitude:     params[:longitude],
          event_date:    params[:event_date],
          emotion_tags:  params[:emotion_tags] || [],
          width:         params[:width],
          height:        params[:height]
        )

        @chapter.touch_last_memory!

        # Queue welcome card on user's first memory ever
        if current_user.welcomed_at.nil?
          DailyCardQueueEntry.schedule!(
            user:           current_user,
            chapter:        @chapter,
            trigger_type:   "welcome",
            preferred_date: Date.current
          )
          current_user.update_column(:welcomed_at, Time.current)
        end

        # Notify the other member
        partner = @chapter.other_member(current_user)
        NotifyNewMemoryJob.perform_later(memory_id: memory.id, recipient_id: partner.id) if partner

        render json: memory_json(memory), status: :created
      end

      # PATCH /api/v1/chapters/:chapter_id/memories/:id
      # Body: { caption:, location_name:, taken_at: }
      def update
        memory = @chapter.memories.find(params[:id])

        unless memory.owner_id == current_user.id
          return render json: { error: "forbidden" }, status: :forbidden
        end

        memory.update!(
          caption:       params.key?(:caption) ? params[:caption] : memory.caption,
          location_name: params.key?(:location_name) ? params[:location_name] : memory.location_name,
          taken_at:      params.key?(:taken_at) ? params[:taken_at] : memory.taken_at
        )

        render json: memory_json(memory), status: :ok
      end

      # GET /api/v1/chapters/:chapter_id/memories/:id/refresh_url
      # Returns a fresh signed media URL. Call when local TTL exceeds 50 minutes.
      def refresh_url
        memory = @chapter.memories_visible_to(current_user).find(params[:id])
        render json: { media_url: memory.signed_url }
      end

      # DELETE /api/v1/chapters/:chapter_id/memories/:id
      def destroy
        memory = @chapter.memories.find(params[:id])

        unless memory.owner_id == current_user.id
          return render json: { error: "forbidden" }, status: :forbidden
        end

        memory.destroy!
        head :no_content
      end

      private

      def set_chapter
        @chapter = Chapter.where(status: %w[pending active])
                          .for_user(current_user)
                          .find(params[:chapter_id])
      end

      def memory_json(memory)
        {
          id:            memory.id,
          chapter_id:    memory.chapter_id,
          owner_id:      memory.owner_id,
          media_url:     memory.s3_key.present? ? memory.signed_url : nil,
          media_type:    memory.media_type,
          caption:       memory.caption,
          taken_at:      memory.taken_at,
          event_date:    memory.event_date,
          emotion_tags:  memory.emotion_tags,
          width:         memory.width,
          height:        memory.height,
          visibility:    memory.visibility,
          location_name: memory.location_name,
          latitude:      memory.latitude,
          longitude:     memory.longitude,
          created_at:    memory.created_at
        }
      end
    end
  end
end
