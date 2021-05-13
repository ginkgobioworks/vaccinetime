require 'discordrb/webhooks'

class FakeDiscord

    def initialize(logger)
        @logger = logger
        end
    
        def update(str)
        @logger.info "[FakeDiscord]: #{str}"
        end

class DiscordClient

  def initialize(logger)
    @logger = logger
    @discord = if ENV['ENVIRONMENT'] != 'test' && env_keys_exist?
                 Discordrb::Webhooks::Client.new(url: ENV['DISCORD_WEBHOOK_URL']).freeze
               end
  end

  def env_keys_exist?
    ENV['DISCORD_WEBHOOK_URL']
  end

  def send(clinic)
    @logger.info "[DiscordClient] Sending message for #{clinic.title} (#{clinic.new_appointments} new appointments)"
    text = clinic.discord_text
    if text.is_a?(Array)
      text.each { |t| @discord.execute do |builder|
                    builder.content = text 
                  end
                }
              end
              @discord.execute do |builder|
                builder.content = text 
              end
  end

  rescue => e
    @logger.error "[DiscordClient] error: #{e}"
    raise e unless ENV['ENVIRONMENT'] == 'production' || ENV['ENVIRONMENT'] == 'staging'

    Sentry.capture_exception(e)
  end

  def post(clinics)
    clinics.filter(&:should_discord_message?).each do |clinic|
      send(clinic)
      clinic.save_message_time
    end
  end
end