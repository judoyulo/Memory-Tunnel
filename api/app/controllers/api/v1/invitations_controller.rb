module Api
  module V1
    class InvitationsController < ApplicationController
      # POST /api/v1/invitations
      # Body: { chapter_id:, memory_id: }
      # Creates (or reuses) a pending Invitation for this chapter and returns the share URL.
      # The client displays this URL via Branch.io deferred deep link on the web preview page.
      def create
        chapter = Chapter.active.for_user(current_user).find(params.require(:chapter_id))
        memory  = chapter.memories.find(params.require(:memory_id))

        unless memory.owner_id == current_user.id
          return render json: { error: "forbidden" }, status: :forbidden
        end

        # Reuse any still-active invitation for this chapter to avoid link churn
        invitation = chapter.invitations.active.first ||
                     chapter.invitations.create!(
                       invited_by:     current_user,
                       preview_memory: memory
                     )

        render json: invitation_json(invitation), status: :created
      end

      # POST /api/v1/invitations/:id/accept
      # Called by the accepting user after they land on the web preview and install the app.
      # The accept flow via invitation_token in verify_otp is preferred (deferred deep link);
      # this endpoint handles the case where the user is already logged in.
      def accept
        invitation = Invitation.active.find(params[:id])
        result     = invitation.accept!(current_user)

        if result[:success]
          render json: { chapter: chapter_json(result[:chapter]) }, status: :ok
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end

      private

      def invitation_json(invitation)
        {
          id:          invitation.id,
          chapter_id:  invitation.chapter_id,
          token:       invitation.token,
          share_url:   invitation_preview_url(invitation.token),
          expires_at:  invitation.expires_at,
          preview_url: invitation.preview_url
        }
      end

      def chapter_json(chapter)
        partner = chapter.other_member(current_user)
        {
          id:             chapter.id,
          status:         chapter.status,
          name:           chapter.name,
          last_memory_at: chapter.last_memory_at,
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
