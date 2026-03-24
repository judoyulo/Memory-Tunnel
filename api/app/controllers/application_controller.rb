class ApplicationController < ActionController::API
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound,      with: :not_found
  rescue_from ActiveRecord::RecordInvalid,       with: :unprocessable
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  # ── Auth ─────────────────────────────────────────────────────────────────────
  def authenticate!
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")
    raise JWT::DecodeError, "missing token" if token.blank?

    payload = JWT.decode(
      token,
      ENV.fetch("JWT_SECRET"),
      true,
      { algorithm: "HS256" }
    ).first

    @current_user = User.find(payload["sub"])
  rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def current_user
    @current_user
  end

  # ── Error renderers ──────────────────────────────────────────────────────────
  def not_found(_e)
    render json: { error: "Not found" }, status: :not_found
  end

  def unprocessable(e)
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def bad_request(e)
    render json: { error: e.message }, status: :bad_request
  end

  # ── JWT helpers ──────────────────────────────────────────────────────────────
  def issue_jwt(user)
    payload = {
      sub: user.id,
      iat: Time.current.to_i,
      exp: 30.days.from_now.to_i
    }
    JWT.encode(payload, ENV.fetch("JWT_SECRET"), "HS256")
  end

  # ── Pagination ───────────────────────────────────────────────────────────────
  def page
    (params[:page] || 1).to_i.clamp(1, Float::INFINITY)
  end

  def per_page
    (params[:per_page] || 30).to_i.clamp(1, 100)
  end
end
