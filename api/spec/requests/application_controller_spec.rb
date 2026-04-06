require "rails_helper"

RSpec.describe "ApplicationController error handlers", type: :request do
  let(:user) { create(:user) }

  def auth_headers(user)
    payload = { sub: user.id, iat: Time.current.to_i, exp: 30.days.from_now.to_i }
    token = JWT.encode(payload, ENV.fetch("JWT_SECRET", "test_secret"), "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  # Regression: ISSUE-002 — not_found handler leaked full SQL WHERE clause via e.message
  # e.g. "Couldn't find Chapter with 'id'='1' [WHERE \"chapters\".\"status\" = $1 AND ...]"
  # Fixed by returning generic "Not found" from not_found handler.
  # Found by /qa on 2026-03-24
  # Report: .gstack/qa-reports/qa-report-localhost-2026-03-24.md
  describe "rescue_from ActiveRecord::RecordNotFound" do
    it "returns generic 'Not found' without leaking SQL" do
      get "/api/v1/chapters/00000000-0000-0000-0000-000000000000",
          headers: auth_headers(user)

      expect(response).to have_http_status(:not_found)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Not found")
    end

    it "does not include SQL keywords in the error message" do
      get "/api/v1/chapters/00000000-0000-0000-0000-000000000000",
          headers: auth_headers(user)

      body = JSON.parse(response.body)
      error_msg = body["error"].to_s
      expect(error_msg).not_to match(/WHERE/i)
      expect(error_msg).not_to match(/Couldn't find/i)
      expect(error_msg).not_to match(/chapters/i)
      expect(error_msg).not_to include("$1")
    end
  end
end
