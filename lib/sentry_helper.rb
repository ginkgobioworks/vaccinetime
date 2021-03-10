require 'sentry-ruby'

module SentryHelper
  def self.catch_errors(logger, module_name, on_error: [])
    yield
  rescue => e
    logger.error "[#{module_name}] Failed to get appointments: #{e}"
    raise e unless ENV['ENVIRONMENT'] == 'production' || ENV['ENVIRONMENT'] == 'staging'

    Sentry.capture_exception(e)
    on_error
  end
end
