require "rails_helper"

RSpec.describe "Daily Card API", type: :request do
  let(:user)    { create(:user) }
  let(:chapter) { create(:chapter, :active, member_a: user) }

  def auth_headers(u = user)
    payload = { sub: u.id, iat: Time.current.to_i, exp: 30.days.from_now.to_i }
    token = JWT.encode(payload, ENV.fetch("JWT_SECRET", "test_secret"), "HS256")
    { "Authorization" => "Bearer #{token}" }
  end

  def create_queue_entry(attrs = {})
    DailyCardQueueEntry.create!(
      {
        user:          user,
        chapter:       chapter,
        trigger_type:  "decay",
        scheduled_for: Date.current,
        priority:      2
      }.merge(attrs)
    )
  end

  # ── GET /api/v1/daily_card ────────────────────────────────────

  describe "GET /api/v1/daily_card" do
    context "when a card is queued for today and not yet delivered" do
      it "returns 200 and marks the entry as delivered" do
        entry = create_queue_entry

        get "/api/v1/daily_card", headers: auth_headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["id"]).to eq(entry.id)
        expect(body["trigger_type"]).to eq("decay")
        expect(entry.reload.delivered_at).not_to be_nil
      end
    end

    context "when no card is queued for today" do
      it "returns 204 no content" do
        get "/api/v1/daily_card", headers: auth_headers

        expect(response).to have_http_status(:no_content)
      end
    end

    context "when a card was already delivered today" do
      it "returns 204 (idempotent — no double delivery)" do
        create_queue_entry(delivered_at: 1.hour.ago)

        get "/api/v1/daily_card", headers: auth_headers

        expect(response).to have_http_status(:no_content)
      end
    end

    it "returns 401 without authentication" do
      get "/api/v1/daily_card"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── POST /api/v1/daily_card/birthday_signal ───────────────────

  describe "POST /api/v1/daily_card/birthday_signal" do
    context "when no birthday card exists for today" do
      it "queues a birthday card and returns 200" do
        expect {
          post "/api/v1/daily_card/birthday_signal",
               params:  { chapter_id: chapter.id },
               headers: auth_headers,
               as:      :json
        }.to change(DailyCardQueueEntry, :count).by(1)

        expect(response).to have_http_status(:ok)
        entry = DailyCardQueueEntry.last
        expect(entry.trigger_type).to eq("birthday")
        expect(entry.priority).to eq(1)
        expect(entry.scheduled_for).to eq(Date.current)
      end
    end

    context "when a birthday card is already queued today (exists? path)" do
      it "is idempotent — does not create a duplicate, returns 200" do
        create_queue_entry(trigger_type: "birthday", priority: 1)

        expect {
          post "/api/v1/daily_card/birthday_signal",
               params:  { chapter_id: chapter.id },
               headers: auth_headers,
               as:      :json
        }.not_to change(DailyCardQueueEntry, :count)

        expect(response).to have_http_status(:ok)
      end
    end

    context "when a race condition triggers RecordNotUnique (regression: TOCTOU fix)" do
      it "rescues the uniqueness violation and returns 200" do
        # Simulate the race: exists? returns false, but insert hits the unique index
        allow(DailyCardQueueEntry).to receive(:exists?).and_return(false)
        allow_any_instance_of(DailyCardQueueEntry).to receive(:save!).and_raise(
          ActiveRecord::RecordNotUnique.new("duplicate key")
        )
        allow(DailyCardQueueEntry).to receive(:create!).and_raise(
          ActiveRecord::RecordNotUnique.new("duplicate key")
        )

        post "/api/v1/daily_card/birthday_signal",
             params:  { chapter_id: chapter.id },
             headers: auth_headers,
             as:      :json

        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 404 for a chapter not belonging to the current user" do
      other_chapter = create(:chapter, :active)

      post "/api/v1/daily_card/birthday_signal",
           params:  { chapter_id: other_chapter.id },
           headers: auth_headers,
           as:      :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a pending chapter (regression: birthday cards require active chapter)" do
      pending_chapter = create(:chapter, member_a: user)   # default status: pending

      post "/api/v1/daily_card/birthday_signal",
           params:  { chapter_id: pending_chapter.id },
           headers: auth_headers,
           as:      :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      post "/api/v1/daily_card/birthday_signal",
           params: { chapter_id: chapter.id },
           as:     :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── POST /api/v1/daily_card/open ─────────────────────────────

  describe "POST /api/v1/daily_card/open" do
    context "when a delivered card exists" do
      it "sets opened_at on first call" do
        entry = create_queue_entry(delivered_at: 1.minute.ago)

        post "/api/v1/daily_card/open", headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(entry.reload.opened_at).not_to be_nil
      end

      it "does not overwrite opened_at on subsequent calls (regression: idempotency fix)" do
        first_open = 5.minutes.ago
        entry = create_queue_entry(delivered_at: 10.minutes.ago, opened_at: first_open)

        post "/api/v1/daily_card/open", headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(entry.reload.opened_at).to be_within(1.second).of(first_open)
      end
    end

    context "when no delivered card exists" do
      it "no-ops and returns 200" do
        post "/api/v1/daily_card/open", headers: auth_headers

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
