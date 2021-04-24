require_relative './base_clinic'

class PharmacyClinic < BaseClinic
  DEFAULT_TWEET_THRESHOLD = 10
  DEFAULT_TWEET_INCREASE_NEEDED = 5
  DEFAULT_TWEET_COOLDOWN = 60 * 60 # 1 hour
end
