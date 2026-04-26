Rails.application.routes.draw do
  # Health check
  get "up" => proc { [200, { "Content-Type" => "application/json" }, ['{"status":"ok"}']] }, as: :rails_health_check

  # Invitation web preview (no auth — public)
  get "i/:token" => "invitations#preview", as: :invitation_preview

  namespace :api do
    namespace :v1 do
      # Auth
      post "auth/send_otp"    # POST { phone } → sends SMS OTP
      post "auth/verify_otp"  # POST { phone, code } → returns JWT
      post "auth/dev_login"   # POST { code: "8888" } → fresh user, dev only

      # Current user
      get    "me", to: "me#show"   # GET → current user profile
      patch  "me", to: "me#update" # PATCH → update display_name / push_token
      delete "me", to: "me#destroy" # DELETE → permanent account deletion + cascade

      # Chapters
      resources :chapters, only: %i[index show create destroy] do
        # Memories within a chapter
        resources :memories, only: %i[index create update destroy] do
          # Presigned URL for direct S3 upload
          post "presign", on: :collection
          # Refresh a signed media URL before it expires (TTL 1hr; call at ~50min)
          get  "refresh_url", on: :member
        end
        # Visibility tier
        patch "visibility"
      end

      # Invitations
      resources :invitations, only: %i[create] do
        post "accept", on: :member
      end

      # Invitation preview (unauthenticated — for invited users before signup)
      get "invitation_previews/:token", to: "invitation_previews#show"

      # Daily card queue
      get  "daily_card",                    to: "daily_card#show"
      post "daily_card/open",              to: "daily_card#open"
      post "daily_card/birthday_signal",   to: "daily_card#birthday_signal"
    end
  end
end
