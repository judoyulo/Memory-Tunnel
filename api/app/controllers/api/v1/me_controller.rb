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
