module Api
  module V1
    class ChaptersController < ApplicationController
      before_action :set_chapter, only: %i[show visibility]

      # GET /api/v1/chapters
      def index
        chapters = Chapter.active.for_user(current_user).includes(:member_a, :member_b)
        render json: chapters.map { |c| chapter_json(c) }
      end

      # GET /api/v1/chapters/:id
      def show
        render json: chapter_json(@chapter)
      end

      # PATCH /api/v1/chapters/:id/visibility
      # Body: { visibility: "all" | "this_item" }
      # Sets the current user's visibility tier for ALL their memories in this chapter.
      def visibility
        vis = params.require(:visibility)
        unless Memory.visibilities.key?(vis)
          return render json: { error: "visibility must be 'this_item' or 'all'" }, status: :unprocessable_entity
        end

        @chapter.memories.where(owner: current_user).update_all(visibility: vis)
        render json: { visibility: vis }, status: :ok
      end

      private

      def set_chapter
        @chapter = Chapter.active
                          .for_user(current_user)
                          .find(params[:id])
      end

      def chapter_json(chapter)
        partner = chapter.other_member(current_user)
        {
          id:               chapter.id,
          status:           chapter.status,
          name:             chapter.name,
          life_chapter_tag: chapter.life_chapter_tag,
          last_memory_at:   chapter.last_memory_at,
          partner: {
            id:           partner&.id,
            display_name: partner&.display_name,
            avatar_url:   partner&.avatar_url
          }
        }
      end
    end
  end
end
