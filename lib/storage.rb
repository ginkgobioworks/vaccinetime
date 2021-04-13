require 'redis'
require 'json'

class Storage
  APPOINTMENT_KEY = 'slack-vaccine-appt'.freeze
  POST_KEY        = 'slack-vaccine-post'.freeze
  COOKIES_KEY     = 'vaccine-cookies'.freeze

  def initialize(redis = Redis.new)
    @redis = redis
  end

  def with_prefix(prefix, clinic)
    prefix + ':' + clinic.storage_key
  end

  def set(key, value)
    @redis.set(key, value)
  end

  def get(key)
    @redis.get(key)
  end

  def save_appointments(clinic)
    set(with_prefix(APPOINTMENT_KEY, clinic), clinic.appointments)
  end

  def get_appointments(clinic)
    get(with_prefix(APPOINTMENT_KEY, clinic))
  end

  def save_post_time(clinic)
    set(with_prefix(POST_KEY, clinic), Time.now)
  end

  def get_post_time(clinic)
    get(with_prefix(POST_KEY, clinic))
  end

  def save_cookies(site, cookies, expiration)
    set("#{COOKIES_KEY}:#{site}", { cookies: cookies, expiration: expiration }.to_json)
  end

  def get_cookies(site)
    res = get("#{COOKIES_KEY}:#{site}")
    res && JSON.parse(res)
  end
end
