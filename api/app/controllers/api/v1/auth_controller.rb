module Api
  module V1
    class AuthController < ApplicationController
      skip_before_action :authenticate!

      # Rate limiting — uses Rails.cache (memory_store in dev, null_store in test)
      # send_otp: 5 requests / minute / IP  → prevents SMS bombing
      rate_limit to: 5, within: 1.minute, only: :send_otp,
                 with: -> { render json: { error: "Too many requests. Try again in a minute." }, status: :too_many_requests }

      # verify_otp: 5 attempts / 10 minutes / phone → prevents brute-force
      rate_limit to: 5, within: 10.minutes, only: :verify_otp,
                 by: -> { params[:phone].to_s.strip },
                 with: -> { render json: { error: "Too many attempts. Try again later." }, status: :too_many_requests }

      # POST /api/v1/auth/send_otp
      # Body: { phone: "+14155551234" }
      # Sends a 6-digit SMS OTP. Idempotent — safe to call again if code expires.
      def send_otp
        phone = params.require(:phone).strip
        user  = User.find_or_initialize_by(phone: phone)

        if user.new_record?
          user.display_name = "User"  # Placeholder; user sets it after OTP verify
          user.save!
        end

        code = user.generate_otp!
        TwilioOtpJob.perform_later(phone: phone, code: code)

        response_body = { message: "OTP sent" }
        response_body[:dev_code] = code if Rails.env.local?
        render json: response_body, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      # POST /api/v1/auth/verify_otp
      # Body: { phone: "+14155551234", code: "123456", display_name: "Xuan", invitation_token: "..." }
      # Returns: { token: "<JWT>", user: { ... } }
      def verify_otp
        phone        = params.require(:phone).strip
        code         = params.require(:code).strip
        display_name = params[:display_name]&.strip
        inv_token    = params[:invitation_token]

        user = User.find_by!(phone: phone)

        unless user.verify_otp!(code)
          return render json: { error: "Invalid or expired code" }, status: :unprocessable_entity
        end

        user.update!(display_name: display_name) if display_name.present?

        # If the app passed a Branch.io deferred invitation token, accept it now
        chapter = nil
        if inv_token.present?
          invitation = Invitation.active.find_by(token: inv_token)
          if invitation
            result  = invitation.accept!(user)
            chapter = result[:chapter] if result[:success]
          end
        end

        jwt = issue_jwt(user)

        render json: {
          token: jwt,
          user: user_json(user),
          chapter: chapter ? chapter_json(chapter) : nil
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Phone number not found" }, status: :not_found
      end

      # POST /api/v1/auth/dev_login
      # Body: { code: "8888" }
      # Development only. Creates a fresh user and returns a JWT. For quick testing.
      def dev_login
        unless Rails.env.local?
          return render json: { error: "Not available in production" }, status: :forbidden
        end

        unless params[:code] == "8888"
          return render json: { error: "Invalid developer code" }, status: :unprocessable_entity
        end

        phone = "+1555#{SecureRandom.random_number(10_000_000).to_s.rjust(7, '0')}"
        user = User.create!(phone: phone, display_name: "User")
        jwt = issue_jwt(user)

        render json: { token: jwt, user: user_json(user), chapter: nil }, status: :ok
      end

      private

      def user_json(user)
        { id: user.id, phone: user.phone, display_name: user.display_name, avatar_url: user.avatar_url, created_at: user.created_at }
      end

      def chapter_json(chapter)
        { id: chapter.id, status: chapter.status }
      end
    end
  end
end
