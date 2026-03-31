require "rails_helper"

RSpec.describe "Memories API", type: :request do
  let(:user)    { create(:user) }
  let(:chapter) { create(:chapter, :active, member_a: user) }

  def auth_headers(u = user)
    payload = { sub: u.id, iat: Time.current.to_i, exp: 30.days.from_now.to_i }
    token = JWT.encode(payload, ENV.fetch("JWT_SECRET", "test_secret"), "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/v1/chapters/:chapter_id/memories" do
    let(:valid_key) { "memories/#{chapter.id}/#{SecureRandom.uuid}.jpg" }

    it "creates a memory with a valid s3_key and returns 201" do
      post "/api/v1/chapters/#{chapter.id}/memories",
           params:  { s3_key: valid_key, visibility: "this_item" },
           headers: auth_headers,
           as:      :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["id"]).to be_present
      expect(body["owner_id"]).to eq(user.id)
      expect(body["visibility"]).to eq("this_item")
    end

    it "rejects an s3_key that doesn't belong to this chapter (path traversal guard)" do
      other_chapter_id = SecureRandom.uuid
      malicious_key = "memories/#{other_chapter_id}/evil.jpg"

      post "/api/v1/chapters/#{chapter.id}/memories",
           params:  { s3_key: malicious_key },
           headers: auth_headers,
           as:      :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("invalid s3_key")
    end

    it "returns 401 without authentication" do
      post "/api/v1/chapters/#{chapter.id}/memories",
           params: { s3_key: valid_key },
           as:     :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/chapters/:chapter_id/memories/:id" do
    let(:memory) { create(:memory, chapter: chapter, owner: user, s3_key: "memories/#{chapter.id}/#{SecureRandom.uuid}.jpg") }

    it "allows the owner to delete their memory" do
      delete "/api/v1/chapters/#{chapter.id}/memories/#{memory.id}",
             headers: auth_headers

      expect(response).to have_http_status(:no_content)
      expect(Memory.find_by(id: memory.id)).to be_nil
    end

    it "returns 403 when a non-owner tries to delete" do
      other_user = create(:user)
      chapter.update!(member_b: other_user)

      delete "/api/v1/chapters/#{chapter.id}/memories/#{memory.id}",
             headers: auth_headers(other_user)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
