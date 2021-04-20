require 'twitter'

class FakeTwitter
  def initialize(logger)
    @logger = logger
  end

  def update(str)
    @logger.info "[FakeTwitter]: #{str}"
  end
end

class TwitterClient

  def initialize(logger)
    @logger = logger
    @twitter = if ENV['ENVIRONMENT'] != 'test' && env_keys_exist?
                 Twitter::REST::Client.new do |config|
                   config.consumer_key        = ENV['TWITTER_CONSUMER_KEY']
                   config.consumer_secret     = ENV['TWITTER_CONSUMER_SECRET']
                   config.access_token        = ENV['TWITTER_ACCESS_TOKEN']
                   config.access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
                 end
               else
                 FakeTwitter.new(logger)
               end
  end

  def env_keys_exist?
    ENV['TWITTER_CONSUMER_KEY'] &&
      ENV['TWITTER_CONSUMER_SECRET'] &&
      ENV['TWITTER_ACCESS_TOKEN'] &&
      ENV['TWITTER_ACCESS_TOKEN_SECRET']
  end

  def tweet(clinic)
    @logger.info "[TwitterClient] Sending tweet for #{clinic.title} (#{clinic.new_appointments} new appointments)"
    text = clinic.twitter_text
    if text.is_a?(Array)
      text.each { |t| @twitter.update(t) }
    else
      @twitter.update(text)
    end
  end

  rescue => e
    @logger.error "[TwitterClient] error: #{e}"
    raise e unless ENV['ENVIRONMENT'] == 'production' || ENV['ENVIRONMENT'] == 'staging'

    Sentry.capture_exception(e)
  end

  def post(clinics)
    clinics.filter(&:should_tweet?).each do |clinic|
      tweet(clinic)
      clinic.save_tweet_time
    end
  end