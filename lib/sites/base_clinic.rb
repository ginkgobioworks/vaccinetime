require 'date'

class BaseClinic
  TWEET_THRESHOLD = 10 # minimum number to post
  TWEET_INCREASE_NEEDED = 5
  TWEET_COOLDOWN = 600 # 10 minutes

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
    raise NotImplementedError
  end

  def render_appointments
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
        text: "*#{title}*\n*Available appointments:* #{render_appointments}\n*Link:* #{link}",
      },
    }
  end

  def has_not_posted_recently?
    (Time.now - last_posted_time) > TWEET_COOLDOWN # 10 minutes
  end


  def should_tweet?
    link &&
      appointments > TWEET_THRESHOLD &&
      new_appointments > TWEET_INCREASE_NEEDED &&
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
