module Api
  module V1
    class ChaptersController < ApplicationController
      before_action :set_chapter, only: %i[show destroy visibility]

      # GET /api/v1/chapters
      def index
        chapters = Chapter.where(status: %w[pending active])
                          .for_user(current_user)
                          .includes(:member_a, :member_b)
                          .order(updated_at: :desc)
        render json: chapters.map { |c| chapter_json(c) }
      end

      # POST /api/v1/chapters
      # Body: { name: "Mom" }  (optional)
      # Creates a new pending chapter for the current user.
      def create
        chapter = Chapter.new(
          member_a:      current_user,
          status:        :pending,
          name:          params[:name]&.strip.presence,
          invited_phone: nil
        )

        if chapter.save
          render json: chapter_json(chapter), status: :created
        else
          render json: { error: chapter.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/chapters/:id
      def show
        render json: chapter_json(@chapter)
      end

      # DELETE /api/v1/chapters/:id
      # Only the creator (member_a) can delete. Active chapters with a partner require
      # both members to leave (not implemented in v1 — only pending chapters are deletable).
      def destroy
        unless @chapter.member_a_id == current_user.id
          return render json: { error: "Only the chapter creator can delete it" }, status: :forbidden
        end

        if @chapter.status == "active" && @chapter.member_b_id.present?
          return render json: { error: "Cannot delete an active chapter with a partner" }, status: :unprocessable_entity
        end

        # Delete invitations first (they reference preview_memory which references this chapter)
        @chapter.invitations.destroy_all
        @chapter.destroy!
        head :no_content
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
        @chapter = Chapter.where(status: %w[pending active])
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
