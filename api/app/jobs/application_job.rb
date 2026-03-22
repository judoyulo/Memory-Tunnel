class ApplicationJob < ActiveJob::Base
  # GoodJob adapter is configured in config/application.rb.
  # Retry with exponential backoff; discard after 3 attempts to prevent
  # infinite dead-letter loops for transient external-service errors.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
end
