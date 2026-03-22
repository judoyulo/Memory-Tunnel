# Notifies the invitation sender when the recipient accepts and installs the app.
# Enqueued from Invitation#accept! inside the acceptance transaction.
class NotifyInvitationAcceptedJob < ApplicationJob
  queue_as :default

  def perform(invitation_id:)
    invitation = Invitation.find(invitation_id)
    sender     = invitation.invited_by
    chapter    = invitation.chapter
    acceptor   = chapter.other_member(sender)

    return unless sender.push_token.present? && acceptor.present?

    ApnsService.send!(
      push_token: sender.push_token,
      title:      "#{acceptor.display_name} joined Memory Tunnel!",
      body:       "Your shared chapter is ready. Tap to add your first memory.",
      data:       {
        type:       "invitation_accepted",
        chapter_id: chapter.id
      }
    )
  end
end
