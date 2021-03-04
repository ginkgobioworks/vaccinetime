require 'slack-ruby-client'

class FakeSlack
  def initialize(logger)
    @logger = logger
  end

  def chat_postMessage(channel:, blocks:, username:, icon_emoji:)
    @logger.info "[FakeSlack]: #{username} (#{icon_emoji}) to #{channel} - #{blocks}"
  end
end

class SlackClient
  DEFAULT_SLACK_CHANNEL  = '#bot-vaccine'.freeze
  DEFAULT_SLACK_USERNAME = 'vaccine-bot'.freeze
  DEFAULT_SLACK_ICON     = ':old-man-yells-at-covid19:'.freeze

  def initialize(logger)
    @logger = logger
    @client = if ENV['ENVIRONMENT'] != 'test' && ENV['SLACK_API_TOKEN']
                init_slack_client
              else
                FakeSlack.new(logger)
              end
  end

  def init_slack_client
    Slack.configure do |config|
      config.token = ENV['SLACK_API_TOKEN']
    end

    slack_client = Slack::Web::Client.new
    slack_client.auth_test
    slack_client
  end

  def send(clinics)
    clinics.each do |clinic|
      @logger.info "[SlackClient] Sending slack for #{clinic.title} (#{clinic.new_appointments} new appointments)"
    end

    @client.chat_postMessage(
      blocks: clinics.map(&:slack_blocks),
      channel: ENV['SLACK_CHANNEL'] || DEFAULT_SLACK_CHANNEL,
      username: ENV['SLACK_USERNAME'] || DEFAULT_SLACK_USERNAME,
      icon_emoji: ENV['SLACK_ICON'] || DEFAULT_SLACK_ICON
    )

  rescue => e
    @logger.error "[SlackClient] error: #{e}"
    Sentry.capture_exception(e)
  end

  def should_post?(clinic)
    clinic.link &&
      clinic.appointments.positive? &&
      clinic.new_appointments.positive?
  end

  def post(clinics)
    clinics_to_slack = clinics.filter { |clinic| should_post?(clinic) }
    send(clinics_to_slack) if clinics_to_slack.any?
  end
end
