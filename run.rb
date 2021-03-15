require 'optparse'
require 'sentry-ruby'

require_relative 'lib/multi_logger'
require_relative 'lib/storage'
require_relative 'lib/slack'
require_relative 'lib/twitter'

# Sites
require_relative 'lib/sites/ma_immunizations'
require_relative 'lib/sites/curative'
require_relative 'lib/sites/color'
require_relative 'lib/sites/cvs'
require_relative 'lib/sites/lowell_general'
require_relative 'lib/sites/my_chart'
require_relative 'lib/sites/zocdoc'

UPDATE_FREQUENCY = ENV['UPDATE_FREQUENCY'] || 60 # seconds

SCRAPERS = {
  'curative' => Curative,
  'color' => Color,
  'cvs' => Cvs,
  'lowell_general' => LowellGeneral,
  'my_chart' => MyChart,
  'ma_immunizations' => MaImmunizations,
  'zocdoc' => Zocdoc,
}.freeze

def all_clinics(scraper, storage, logger)
  if scraper == 'all'
    SCRAPERS.values.flat_map do |scraper_module|
      scraper_module.all_clinics(storage, logger)
    end
  else
    scraper_module = SCRAPERS[scraper]
    raise "Module #{scraper} not found" unless scraper_module

    scraper_module.all_clinics(storage, logger)
  end
end

def main(scraper: 'all')
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
    all_clinics(scraper, storage, logger).each(&:save_appointments)
    logger.info '[Main] Done seeding redis'
    sleep(UPDATE_FREQUENCY)
  end

  loop do
    logger.info '[Main] Started checking'
    clinics = all_clinics(scraper, storage, logger)

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

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby run.rb [options]"

  opts.on('-s', '--scraper SCRAPER', SCRAPERS.keys, "Scraper to run, choose from: #{SCRAPERS.keys.join(', ')}") do |s|
    options[:scraper] = s
  end
end.parse!

main(**options)
