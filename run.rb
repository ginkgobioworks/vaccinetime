require 'sentry-ruby'

require_relative 'lib/multi_logger'
require_relative 'lib/storage'
require_relative 'lib/slack'
require_relative 'lib/twitter'

# Sites
require_relative 'lib/sites/ma_immunizations'
require_relative 'lib/sites/curative'
require_relative 'lib/sites/color'

UPDATE_FREQUENCY = ENV['UPDATE_FREQUENCY'] || 60 # seconds

def all_clinics(storage, logger)
  Curative.all_clinics(storage, logger) +
    Color.all_clinics(storage, logger) +
    MaImmunizations.all_clinics(storage, logger)
end

def main
  environment = ENV['ENVIRONMENT'] || 'dev'

  if ENV['SENTRY_DSN']
    Sentry.init do |config|
      config.dsn = ENV['SENTRY_DSN']
      config.environment = environment
    end
  end

  logger = MultiLogger.new(
    Logger.new($stdout),
    Logger.new("log/#{environment}.txt", 'daily')
  )
  storage = Storage.new
  slack = SlackClient.new(logger)
  twitter = TwitterClient.new(logger)

  logger.info "[Main] Update frequency is set to every #{UPDATE_FREQUENCY} seconds"

  if ENV['SEED_REDIS']
    logger.info '[Main] Seeding redis with current appointments'
    all_clinics(storage, logger).each(&:save_appointments)
    logger.info '[Main] Done seeding redis'
    sleep(UPDATE_FREQUENCY)
  end

  loop do
    logger.info '[Main] Started checking'
    clinics = all_clinics(storage, logger)

    slack.post(clinics)
    twitter.post(clinics)

    clinics.each(&:save_appointments)

    logger.info '[Main] Done checking'
    sleep(UPDATE_FREQUENCY)
  end

rescue => e
  Sentry.capture_exception(e)
  logger.error "[Main] Error: #{e}"
  raise
end

main
