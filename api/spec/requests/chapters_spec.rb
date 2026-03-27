require "rails_helper"

RSpec.describe "Chapters API", type: :request do
  let(:user) { create(:user) }

  def auth_headers(u = user)
    payload = { sub: u.id, iat: Time.current.to_i, exp: 30.days.from_now.to_i }
    token = JWT.encode(payload, ENV.fetch("JWT_SECRET", "test_secret"), "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/v1/chapters" do
    it "creates a pending chapter and returns 201" do
      post "/api/v1/chapters", params: { name: "Alice" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["id"]).to be_present
      expect(body["status"]).to eq("pending")
    end

    it "sets the current user as member_a" do
      post "/api/v1/chapters", params: { name: "Alice" }, headers: auth_headers, as: :json

      chapter = Chapter.find(JSON.parse(response.body)["id"])
      expect(chapter.member_a_id).to eq(user.id)
    end

    it "persists the name when provided" do
      post "/api/v1/chapters", params: { name: "  Bob  " }, headers: auth_headers, as: :json

      chapter = Chapter.find(JSON.parse(response.body)["id"])
      expect(chapter.name).to eq("Bob")
    end

    it "accepts a request without a name" do
      post "/api/v1/chapters", params: {}, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      chapter = Chapter.find(JSON.parse(response.body)["id"])
      expect(chapter.name).to be_nil
    end

    it "returns 401 without authentication" do
      post "/api/v1/chapters", params: { name: "Alice" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
