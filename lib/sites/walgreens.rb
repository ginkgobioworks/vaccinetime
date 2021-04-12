require 'json'
require 'date'
require 'rest-client'

require_relative '../sentry_helper'
require_relative '../browser'
require_relative './base_clinic'

module Walgreens
  COOKIE_STORAGE = 'walgreens-cookies'
  ACCOUNT_URL = 'https://www.walgreens.com/youraccount/default.jsp'.freeze
  SIGN_UP_URL = 'https://www.walgreens.com/findcare/vaccination/covid-19/'.freeze
  LOGIN_URL = 'https://www.walgreens.com/login.jsp'.freeze
  API_URL = 'https://www.walgreens.com/hcschedulersvc/svc/v2/immunizationLocations/timeslots'.freeze
  USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.114 Safari/537.36'.freeze

  # https://www.mapdevelopers.com/draw-circle-tool.php?circles=%5B%5B40233.5%2C42.3520885%2C-71.4868472%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%2C%5B40233.5%2C41.8628846%2C-70.9477294%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%2C%5B40233.5%2C41.7814149%2C-70.3310229%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%2C%5B40233.5%2C42.3744147%2C-72.5757593%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%2C%5B40233.5%2C42.36567%2C-72.0101209%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%2C%5B40233.5%2C42.3857057%2C-73.1035201%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%2C%5B40233.5%2C42.5305705%2C-70.8835315%2C%22%23AAAAAA%22%2C%22%23000000%22%2C0.4%5D%5D
  LOCATIONS = [
    { latitude: 42.385706, longitude: -73.103520 },
    { latitude: 42.374415, longitude: -72.575759 },
    { latitude: 42.365670, longitude: -72.010121 },
    { latitude: 42.352089, longitude: -71.486847 },
    { latitude: 42.530571, longitude: -70.883532 },
    { latitude: 41.862885, longitude: -70.947729 },
    { latitude: 41.781415, longitude: -70.331023 },
  ].freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Walgreens') do
      logger.info '[Walgreens] Checking site'
      cookies = stored_cookies(storage).each_with_object({}) { |c, h| h[c[:name]] = c[:value] }
      cookies = refresh_cookies(storage, logger) if cookies.empty?
      cities = LOCATIONS.flat_map do |loc|
        retried = false
        random_wait 2
        begin
          fetch_stores(cookies, loc[:latitude], loc[:longitude])
        rescue RestClient::Unauthorized => e
          cookies = refresh_cookies(storage, logger)
          raise e if retried

          retried = true
          retry
        end
      end.uniq
      logger.info "[Walgreens] Found appointments in #{cities.join(', ')}" if cities.any?
      [Clinic.new(storage, cities)]
    end
  end

  def self.fetch_stores(cookies, lat, lon)
    res = JSON.parse(
      RestClient.post(
        API_URL,
        {
          appointmentAvailability: {
            startDateTime: (Date.today + 1).strftime('%Y-%m-%d'),
          },
          position: {
            latitude: lat,
            longitude: lon,
          },
          radius: 25,
          serviceId: '99',
          size: 25,
          state: 'MA',
          vaccine: {
            productId: '',
          },
        }.to_json,
        content_type: :json,
        accept: :json,
        user_agent: USER_AGENT,
        cookies: cookies,
        host: 'www.walgreens.com',
        referer: 'https://www.walgreens.com/findcare/vaccination/covid-19/appointment/next-available'
      ).body
    )
    return [] if res['errors']&.any?

    res['locations'].filter do |location|
      location['address']['state'] == 'MA'
    end.map do |location|
      location['address']['city']
    end
  rescue RestClient::NotFound
    []
  end

  def self.stored_cookies(storage)
    JSON.parse(storage.get(COOKIE_STORAGE) || '[]', symbolize_names: true)
  end

  def self.refresh_cookies(storage, logger)
    logger.info '[Walgreens] Refreshing cookies'
    Browser.run do |browser|
      #stored_cookies(storage).each do |cookie|
        #browser.cookies.set(**cookie)
      #end

      browser.goto(ACCOUNT_URL)
      sleep 2
      browser.network.wait_for_idle

      if browser.current_url.start_with?(LOGIN_URL)
        username = Browser.wait_for(browser, 'input#user_name')
        username.focus.type(ENV['WALGREENS_USERNAME'])
        password = Browser.wait_for(browser, 'input#user_password')
        password.focus.type(ENV['WALGREENS_PASSWORD'])

        random_wait(2)
        browser.at_css('button#submit_btn').click

        sleep 2
        browser.network.wait_for_idle
        unless browser.current_url == 'https://www.walgreens.com/youraccount/default.jsp'
          security_q = Browser.wait_for(browser, 'input#radio-security')
          if security_q
            security_q.click
            random_wait(2)
            browser.at_css('button#optionContinue').click
            browser.network.wait_for_idle

            question = Browser.wait_for(browser, 'input#secQues')
            question.focus.type(ENV['WALGREENS_SECURITY_ANSWER'])
            random_wait(2)
            browser.at_css('button#validate_security_answer').click
            browser.network.wait_for_idle
          end
        end
      end

      storage.set(
        COOKIE_STORAGE,
        browser.cookies.all.values.map do |cookie|
          {
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
          }
        end.to_json
      )

      browser.cookies.all.values.each_with_object({}) { |c, h| h[c.name] = c.value }
    end
  end

  def self.random_wait(base_wait)
    sleep(base_wait + ((-10..10).to_a.sample.to_f / 10))
  end

  class Clinic < BaseClinic
    TWEET_THRESHOLD = ENV['PHARMACY_TWEET_THRESHOLD']&.to_i || BaseClinic::PHARMACY_TWEET_THRESHOLD
    TWEET_INCREASE_NEEDED = ENV['PHARMACY_TWEET_INCREASE_NEEDED']&.to_i || BaseClinic::PHARMACY_TWEET_INCREASE_NEEDED
    TWEET_COOLDOWN = ENV['PHARMACY_TWEET_COOLDOWN']&.to_i || BaseClinic::TWEET_COOLDOWN

    attr_reader :cities

    def initialize(storage, cities)
      super(storage)
      @cities = cities
    end

    def title
      'Walgreens'
    end

    def link
      SIGN_UP_URL
    end

    def appointments
      cities.length
    end

    def storage_key
      'walgreens-last-cities'
    end

    def save_appointments
      @storage.set(storage_key, cities.to_json)
    end

    def last_cities
      stored_value = @storage.get(storage_key)
      stored_value.nil? ? [] : JSON.parse(stored_value)
    end

    def new_cities
      cities - last_cities
    end

    def new_appointments
      new_cities.length
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Available appointments in:* #{cities.join(', ')}\n*Link:* #{link}",
        },
      }
    end

    def twitter_text
      tweet_groups = []

      #  27 chars: " appointments available in "
      #  35 chars: ". Check eligibility and sign up at "
      #  23 chars: shortened link
      # ---------
      # 280 chars total, 280 is the maximum
      text_limit = 280 - (title.length + 27 + 35 + 23)

      tweet_cities = cities
      cities_text = tweet_cities.shift
      while (city = tweet_cities.shift)
        pending_text = ", #{city}"
        if cities_text.length + pending_text.length > text_limit
          tweet_groups << cities_text
          cities_text = city
        else
          cities_text += pending_text
        end
      end
      tweet_groups << cities_text

      tweet_groups.map do |group|
        "#{title} appointments available in #{group}. Check eligibility and sign up at #{sign_up_page}"
      end
    end
  end
end
