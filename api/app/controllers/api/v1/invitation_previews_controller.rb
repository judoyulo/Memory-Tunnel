module Api
  module V1
    # Unauthenticated endpoint for invited users to preview a chapter before signing up.
    # The invitation token in the URL is the only auth — it's a 32-byte random UUID.
    class InvitationPreviewsController < ApplicationController
      skip_before_action :authenticate!

      # GET /api/v1/invitation_previews/:token
      def show
        invitation = Invitation.active.find_by!(token: params[:token])
        chapter    = invitation.chapter
        inviter    = invitation.invited_by
        memory     = invitation.preview_memory

        render json: {
          inviter_name:      inviter.display_name,
          chapter_name:      chapter.name,
          preview_image_url: memory&.signed_url,
          invitation_id:     invitation.id
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invitation not found or expired" }, status: :not_found
      end
    end
  end
end
