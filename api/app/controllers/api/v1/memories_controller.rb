module Api
  module V1
    class MemoriesController < ApplicationController
      before_action :set_chapter

      # GET /api/v1/chapters/:chapter_id/memories
      # Returns all memories visible to the current user in this chapter,
      # ordered by effective date descending.
      def index
        memories = @chapter.memories_visible_to(current_user)
                            .offset((page - 1) * per_page)
                            .limit(per_page)
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
        memory = @chapter.memories.create!(
          owner:      current_user,
          s3_key:     params.require(:s3_key),
          caption:    params[:caption],
          taken_at:   params[:taken_at],
          visibility: params.fetch(:visibility, "this_item"),
          media_type: params.fetch(:media_type, "photo")
        )

        @chapter.touch_last_memory!

        # Notify the other member
        partner = @chapter.other_member(current_user)
        NotifyNewMemoryJob.perform_later(memory_id: memory.id, recipient_id: partner.id) if partner

        render json: memory_json(memory), status: :created
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
          id:          memory.id,
          chapter_id:  memory.chapter_id,
          owner_id:    memory.owner_id,
          media_url:   memory.signed_url,
          media_type:  memory.media_type,
          caption:     memory.caption,
          taken_at:    memory.taken_at,
          visibility:  memory.visibility,
          created_at:  memory.created_at
        }
      end
    end
  end
end
