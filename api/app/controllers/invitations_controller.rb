# Public (unauthenticated) web preview for invitation links.
# Rendered at GET /i/:token — the landing page a recipient sees before installing the app.
class InvitationsController < ActionController::Base
  layout "invitation"

  # Rails app is API-mode by default, which sets Content-Type: application/json on
  # responses. Force HTML for this controller so receivers see a rendered page,
  # not raw HTML source.
  before_action :force_html_response

  # GET /i/:token
  def preview
    @invitation = Invitation.active.find_by!(token: params[:token])
    @memory     = @invitation.preview_memory
    @sender     = @invitation.invited_by
    @preview_url = @invitation.preview_url   # 1-hr presigned S3 URL

    # Branch.io deferred deep link data embedded in the page so the SDK
    # can route new installs directly to the accept flow.
    @branch_data = {
      invitation_token: @invitation.token,
      sender_name:      @sender.display_name
    }
  rescue ActiveRecord::RecordNotFound
    render "expired", status: :gone
  end

  private

  def force_html_response
    request.format = :html
    response.content_type = "text/html; charset=utf-8"
  end
end
