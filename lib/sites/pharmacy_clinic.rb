require_relative './base_clinic'

class PharmacyClinic < BaseClinic
  DEFAULT_TWEET_THRESHOLD = 5
  DEFAULT_TWEET_INCREASE_NEEDED = 2
  DEFAULT_TWEET_COOLDOWN = 30 * 60 # 30 minutes
end
