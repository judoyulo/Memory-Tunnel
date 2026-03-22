require "twilio-ruby"

# Sends a one-time password via Twilio SMS.
# Enqueued from AuthController#send_otp.
class TwilioOtpJob < ApplicationJob
  queue_as :critical

  def perform(phone:, code:)
    client = Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )

    client.messages.create(
      from: ENV.fetch("TWILIO_FROM_NUMBER"),
      to:   phone,
      body: "Your Memory Tunnel code is #{code}. It expires in 10 minutes."
    )
  end
end
