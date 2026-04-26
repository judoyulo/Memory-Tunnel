module Api
  module V1
    class MeController < ApplicationController
      # GET /api/v1/me
      def show
        render json: user_json(current_user)
      end

      # PATCH /api/v1/me
      # Body: { display_name:, push_token: }
      # Used on first launch to set display name and register APNs push token.
      def update
        current_user.update!(user_params)
        render json: user_json(current_user)
      end

      # DELETE /api/v1/me
      # Permanently deletes the user and cascades to:
      #   - All memories owned by this user (S3 objects purged via after_destroy_commit)
      #   - All chapters where this user is member_a (and all their memories)
      #   - Chapters where this user is member_b are nullified (partner stays in their lane)
      #   - All invitations sent by this user
      #   - All daily card queue entries for this user
      # Required for Apple App Store compliance + GDPR.
      def destroy
        current_user.destroy!
        render json: { message: "Account deleted" }, status: :ok
      end

      private

      def user_params
        params.permit(:display_name, :push_token)
      end

      def user_json(user)
        {
          id:           user.id,
          phone:        user.phone,
          display_name: user.display_name,
          avatar_url:   user.avatar_url,
          created_at:   user.created_at
        }
      end
    end
  end
end
