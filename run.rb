require 'optparse'
require 'sentry-ruby'

require_relative 'lib/multi_logger'
require_relative 'lib/storage'
require_relative 'lib/slack'
require_relative 'lib/twitter'

# Sites
require_relative 'lib/sites/ma_immunizations'
# require_relative 'lib/sites/curative'
# require_relative 'lib/sites/color'
require_relative 'lib/sites/cvs'
require_relative 'lib/sites/lowell_general'
require_relative 'lib/sites/my_chart'
require_relative 'lib/sites/zocdoc'
require_relative 'lib/sites/acuity'
require_relative 'lib/sites/trinity_health'
require_relative 'lib/sites/southcoast'
require_relative 'lib/sites/northampton'
require_relative 'lib/sites/rutland'
require_relative 'lib/sites/heywood_healthcare'

UPDATE_FREQUENCY = ENV['UPDATE_FREQUENCY']&.to_i || 60 # seconds

SCRAPERS = {
  # 'curative' => Curative,
  # 'color' => Color,
  'cvs' => Cvs,
  'lowell_general' => LowellGeneral,
  'my_chart' => MyChart,
  'ma_immunizations' => MaImmunizations,
  'zocdoc' => Zocdoc,
  'acuity' => Acuity,
  'trinity_health' => TrinityHealth,
  'southcoast' => Southcoast,
  'northampton' => Northampton,
  'rutland' => Rutland,
  'heywood_healthcare' => HeywoodHealthcare,
}.freeze

def all_clinics(scrapers, storage, logger)
  if scrapers == 'all'
    SCRAPERS.values.each do |scraper_module|
      yield scraper_module.all_clinics(storage, logger)
    end
  else
    scrapers.each do |scraper|
      scraper_module = SCRAPERS[scraper]
      raise "Module #{scraper} not found" unless scraper_module

      yield scraper_module.all_clinics(storage, logger)
    end
  end
end

def sleep_for(frequency)
  start_time = Time.now
  yield
  running_time = Time.now - start_time
  sleep([frequency - running_time, 0].max)
end

def main(scrapers: 'all')
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
    sleep_for(UPDATE_FREQUENCY) do
      logger.info '[Main] Seeding redis with current appointments'
      all_clinics(scrapers, storage, logger) { |clinics| clinics.each(&:save_appointments) }
      logger.info '[Main] Done seeding redis'
    end
  end

  loop do
    sleep_for(UPDATE_FREQUENCY) do
      logger.info '[Main] Started checking'
      all_clinics(scrapers, storage, logger) do |clinics|
        slack.post(clinics)
        twitter.post(clinics)

        clinics.each(&:save_appointments)
      end
      logger.info '[Main] Done checking'
    end
  end

rescue => e
  Sentry.capture_exception(e)
  logger.error "[Main] Error: #{e}"
  raise
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby run.rb [options]"

  opts.on('-s', '--scrapers SCRAPER1,SCRAPER2', Array, "Scraper to run, choose from: #{SCRAPERS.keys.join(', ')}") do |s|
    options[:scrapers] = s
  end
end.parse!

main(**options)
