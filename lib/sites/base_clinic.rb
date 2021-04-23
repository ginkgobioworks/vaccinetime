require 'date'

class BaseClinic
  DEFAULT_TWEET_THRESHOLD = 20 # minimum number to post
  DEFAULT_TWEET_INCREASE_NEEDED = 10
  DEFAULT_TWEET_COOLDOWN = 30 * 60 # 30 minutes

  def initialize(storage)
    @storage = storage
  end

  def title
    raise NotImplementedError
  end

  def appointments
    raise NotImplementedError
  end

  def last_appointments
    @storage.get_appointments(self)&.to_i || 0
  end

  def new_appointments
    appointments - last_appointments
  end

  def link
    raise NotImplementedError
  end

  def sign_up_page
    link
  end

  def city
    nil
  end

  def render_slack_appointments
    appointment_txt = "#{appointments} (#{new_appointments} new)"
    if appointments >= 10
      ":siren: #{appointment_txt} :siren:"
    else
      appointment_txt
    end
  end

  def slack_blocks
    {
      type: 'section',
      text: {
        type: 'mrkdwn',
        text: "*#{title}*\n*Available appointments:* #{render_slack_appointments}\n*Link:* #{link}",
      },
    }
  end

  def module_prefix
    @module_prefix ||= self.class.to_s.gsub(/::.*/, '').gsub(/(.)([A-Z])/, '\1_\2').upcase
  end

  def tweet_threshold
    ENV["#{module_prefix}_TWEET_THRESHOLD"] || self.class::DEFAULT_TWEET_THRESHOLD
  end

  def tweet_cooldown
    ENV["#{module_prefix}_TWEET_COOLDOWN"] || self.class::DEFAULT_TWEET_COOLDOWN
  end

  def tweet_increase_needed
    ENV["#{module_prefix}_TWEET_INCREASE_NEEDED"] || self.class::DEFAULT_TWEET_INCREASE_NEEDED
  end

  def has_not_posted_recently?
    (Time.now - last_posted_time) > tweet_cooldown
  end

  def should_tweet?
    !link.nil? &&
      appointments >= tweet_threshold &&
      new_appointments >= tweet_increase_needed &&
      has_not_posted_recently?
  end

  def twitter_text
    "#{appointments} appointments available at #{title}. Check eligibility and sign up at #{sign_up_page}"
  end

  def storage_key
    title
  end

  def save_appointments
    @storage.save_appointments(self)
  end

  def save_tweet_time
    @storage.save_post_time(self)
  end

  def last_posted_time
    DateTime.parse(@storage.get_post_time(self) || '2021-January-1').to_time
  end
end
