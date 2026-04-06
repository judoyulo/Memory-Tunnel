require "rails_helper"

RSpec.describe "Auth API", type: :request do
  describe "POST /api/v1/auth/send_otp" do
    it "returns 200 and message when phone is valid" do
      post "/api/v1/auth/send_otp", params: { phone: "+14155550001" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["message"]).to eq("OTP sent")
    end

    it "includes dev_code in development mode" do
      post "/api/v1/auth/send_otp", params: { phone: "+14155550002" }, as: :json
      body = JSON.parse(response.body)
      expect(body["dev_code"]).to be_present
    end

    it "returns 400 when phone param is missing" do
      post "/api/v1/auth/send_otp", params: {}, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /api/v1/auth/verify_otp" do
    let(:phone) { "+14155550003" }

    before do
      post "/api/v1/auth/send_otp", params: { phone: phone }, as: :json
      @dev_code = JSON.parse(response.body)["dev_code"]
    end

    it "returns JWT and user on valid OTP" do
      post "/api/v1/auth/verify_otp",
           params: { phone: phone, code: @dev_code, display_name: "Test" },
           as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token"]).to be_present
      expect(body["user"]["phone"]).to eq(phone)
    end

    it "returns 422 on wrong OTP code" do
      post "/api/v1/auth/verify_otp",
           params: { phone: phone, code: "000000" },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Invalid or expired code")
    end

    # Regression: ISSUE-001 — verify_otp was leaking SQL query in 404 error message
    # Found by /qa on 2026-03-22
    # Report: .gstack/qa-reports/qa-report-localhost-2026-03-22.md
    it "returns sanitized 404 without SQL disclosure for unknown phone" do
      post "/api/v1/auth/verify_otp",
           params: { phone: "+19999999999", code: "123456" },
           as: :json

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Phone number not found")
      # Must NOT expose SQL internals
      expect(body["error"]).not_to include("WHERE")
      expect(body["error"]).not_to include("users")
      expect(body["error"]).not_to include("Couldn't find")
    end

    # invitation_token flow — user B accepts an invitation during OTP verification
    context "with a valid invitation_token" do
      let(:inviter)     { create(:user) }
      let(:chapter)     { create(:chapter, member_a: inviter, invited_phone: "+14155550099") }
      let(:memory)      { create(:memory, chapter: chapter, owner: inviter) }
      let(:invitation)  { create(:invitation, chapter: chapter, invited_by: inviter, preview_memory: memory) }
      let(:invitee_phone) { "+14155550099" }

      before do
        invitation # ensure it exists
        post "/api/v1/auth/send_otp", params: { phone: invitee_phone }, as: :json
        @dev_code = JSON.parse(response.body)["dev_code"]
      end

      it "returns a chapter in the response when invitation token is valid" do
        post "/api/v1/auth/verify_otp",
             params: { phone: invitee_phone, code: @dev_code, invitation_token: invitation.token },
             as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["token"]).to be_present
        expect(body["chapter"]).not_to be_nil
        expect(body["chapter"]["id"]).to eq(chapter.id)
        expect(body["chapter"]["status"]).to eq("active")
      end

      it "activates the chapter — member_b is set to the invitee" do
        post "/api/v1/auth/verify_otp",
             params: { phone: invitee_phone, code: @dev_code, invitation_token: invitation.token },
             as: :json

        chapter.reload
        invitee = User.find_by!(phone: invitee_phone)
        expect(chapter.member_b_id).to eq(invitee.id)
        expect(chapter.status).to eq("active")
      end

      it "ignores an expired invitation token and returns nil chapter" do
        invitation.update!(expires_at: 1.day.ago)

        post "/api/v1/auth/verify_otp",
             params: { phone: invitee_phone, code: @dev_code, invitation_token: invitation.token },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["chapter"]).to be_nil
      end

      it "ignores an unknown invitation token gracefully" do
        post "/api/v1/auth/verify_otp",
             params: { phone: invitee_phone, code: @dev_code, invitation_token: "bad-token-xyz" },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["chapter"]).to be_nil
      end

      it "rejects the inviter trying to accept their own invitation" do
        # Get the inviter an OTP
        inviter.generate_otp!
        code = inviter.otp_code
        # Directly set a known code for the inviter
        raw = "555555"
        inviter.update!(
          otp_code: BCrypt::Password.create(raw),
          otp_expires_at: 10.minutes.from_now
        )

        post "/api/v1/auth/verify_otp",
             params: { phone: inviter.phone, code: raw, invitation_token: invitation.token },
             as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        # chapter is nil — you cannot accept your own invitation
        expect(body["chapter"]).to be_nil
        invitation.reload
        expect(invitation.accepted_at).to be_nil
      end
    end
  end

  describe "rate limiting" do
    # Rate limiting uses Rails.cache which is :null_store in test — so limits
    # never actually trigger. These tests verify the middleware is wired up and
    # the endpoints behave normally (i.e., aren't broken by the rate_limit call).
    it "send_otp continues to return 200 under normal load" do
      post "/api/v1/auth/send_otp", params: { phone: "+14155550050" }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "verify_otp continues to return errors normally under normal load" do
      post "/api/v1/auth/verify_otp", params: { phone: "+19999999999", code: "000000" }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
