require "twilio-ruby"

# Sends a one-time password via Twilio Verify.
# Enqueued from AuthController#send_otp.
class TwilioOtpJob < ApplicationJob
  queue_as :critical

  def perform(phone:, code: nil)
    client = Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )

    client.verify
      .v2
      .services(ENV.fetch("TWILIO_VERIFY_SID"))
      .verifications
      .create(to: phone, channel: "sms")
  end
end
