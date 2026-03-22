require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"

Bundler.require(*Rails.groups)
require "bcrypt"

module MemoryTunnelApi
  class Application < Rails::Application
    config.load_defaults 8.0

    # api_only = false so InvitationsController can render the HTML web-preview page.
    # All API controllers inherit from ApplicationController < ActionController::API
    # and return JSON; the public invitation preview uses ActionController::Base.
    config.api_only = false

    # GoodJob as the Active Job queue adapter (PostgreSQL-backed, no Redis)
    config.active_job.queue_adapter = :good_job

    # GoodJob cron
    config.good_job.cron = {
      decay_detection: {
        cron:        "0 2 * * *",          # 02:00 UTC nightly
        class:       "DecayDetectionJob",
        description: "Detect quiet chapters and schedule decay reminder cards"
      }
    }

    # Execution mode: :async (threads in web process) or :external (dedicated worker).
    # Set GOOD_JOB_EXECUTION_MODE=external on worker dynos.
    config.good_job.execution_mode = ENV.fetch("GOOD_JOB_EXECUTION_MODE", "async").to_sym
    config.good_job.max_threads    = 5

    # CORS — tightened in production via ALLOWED_ORIGINS env var
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins ENV.fetch("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
        resource "*", headers: :any, methods: %i[get post put patch delete options]
      end
    end

    # All responses are JSON
    config.action_dispatch.default_headers.merge!(
      "Content-Type" => "application/json"
    )
  end
end
