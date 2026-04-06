require "net/http"
require "openssl"
require "json"

# Thin wrapper around Apple APNs HTTP/2 provider API.
# Uses token-based auth (p8 key) — no certificate rotation needed.
#
# Required ENV vars:
#   APNS_KEY_ID        — the 10-char key ID from Apple Developer
#   APNS_TEAM_ID       — the 10-char team ID
#   APNS_BUNDLE_ID     — e.g. "com.memorytunnel.app"
#   APNS_P8_KEY        — PEM content of the .p8 file (newlines as \n)
#   APNS_PRODUCTION    — "true" in production; anything else uses sandbox
class ApnsService
  SANDBOX_HOST    = "api.sandbox.push.apple.com"
  PRODUCTION_HOST = "api.push.apple.com"
  PORT            = 443

  class << self
    # Send a push notification to a single device token.
    #
    # @param push_token [String] APNs device token
    # @param title      [String] notification title
    # @param body       [String] notification body
    # @param data       [Hash]   extra key-value data passed in the payload
    # @param badge      [Integer, nil] badge count to display
    def send!(push_token:, title:, body:, data: {}, badge: nil)
      return if push_token.blank?

      unless configured?
        Rails.logger.warn("[ApnsService] skipping push — APNS_KEY_ID, APNS_TEAM_ID, or APNS_P8_KEY not set")
        return
      end

      payload = build_payload(title: title, body: body, data: data, badge: badge)
      jwt     = build_jwt

      http = Net::HTTP.new(host, PORT)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Post.new("/3/device/#{push_token}")
      request["authorization"]  = "bearer #{jwt}"
      request["apns-push-type"] = "alert"
      request["apns-topic"]     = ENV.fetch("APNS_BUNDLE_ID")
      request["content-type"]   = "application/json"
      request.body = payload.to_json

      response = http.request(request)

      unless response.code == "200"
        Rails.logger.warn("[ApnsService] push failed — token=#{push_token} " \
                          "status=#{response.code} body=#{response.body}")
      end

      response
    end

    def configured?
      ENV["APNS_KEY_ID"].present? && ENV["APNS_TEAM_ID"].present? && ENV["APNS_P8_KEY"].present?
    end

    private

    def host
      ENV["APNS_PRODUCTION"] == "true" ? PRODUCTION_HOST : SANDBOX_HOST
    end

    def build_payload(title:, body:, data:, badge:)
      aps = {
        alert: { title: title, body: body },
        sound: "default"
      }
      aps[:badge] = badge if badge

      { aps: aps }.merge(data)
    end

    # Generates a short-lived ES256 JWT signed with the p8 key.
    # Tokens are valid for 60 minutes; Apple recommends regenerating every 20-30 min.
    # For simplicity, we regenerate on every call — acceptable at low-moderate volume.
    def build_jwt
      header  = { alg: "ES256", kid: ENV.fetch("APNS_KEY_ID") }
      payload = { iss: ENV.fetch("APNS_TEAM_ID"), iat: Time.current.to_i }

      key = OpenSSL::PKey::EC.new(ENV.fetch("APNS_P8_KEY").gsub("\\n", "\n"))

      segments = [
        Base64.urlsafe_encode64(header.to_json, padding: false),
        Base64.urlsafe_encode64(payload.to_json, padding: false)
      ]
      signing_input = segments.join(".")

      signature = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      segments << Base64.urlsafe_encode64(signature, padding: false)
      segments.join(".")
    end
  end
end
