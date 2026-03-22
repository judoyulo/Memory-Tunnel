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
  end
end
