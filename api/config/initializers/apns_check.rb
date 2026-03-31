# Warn on boot if APNs credentials are missing — pushes will silently no-op.
Rails.application.config.after_initialize do
  missing = %w[APNS_KEY_ID APNS_TEAM_ID APNS_P8_KEY].select { |k| ENV[k].blank? }
  if missing.any?
    Rails.logger.warn("[APNs] Missing env vars: #{missing.join(', ')}. Push notifications are disabled.")
  end
end
