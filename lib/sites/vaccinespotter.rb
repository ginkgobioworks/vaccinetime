require 'rest-client'
require 'json'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Vaccinespotter
  API_URL = 'https://www.vaccinespotter.org/api/v0/states/MA.json'.freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Vaccinespotter') do
      logger.info '[Vaccinespotter] Checking site'
      ma_stores.map do |brand, stores|
        logger.info "[Vaccinespotter] Found #{stores.length} #{brand} appointments"
        Clinic.new(storage, brand, stores)
      end
    end
  end

  def self.ma_stores
    ma_data['features'].each_with_object({}) do |feature, h|
      properties = feature['properties']
      next unless properties

      brand = properties['provider_brand_name']
      appointments_available = properties['appointments_available']
      next unless brand && appointments_available && brand != 'CVS'

      h[brand] ||= []
      h[brand] << properties
    end
  end

  def self.ma_data
    JSON.parse(RestClient.get(API_URL).body)
  end

  class Clinic < BaseClinic
    LAST_SEEN_STORAGE_PREFIX = 'vaccinespotter-last-cities'.freeze
    TWEET_THRESHOLD = ENV['PHARMACY_TWEET_THRESHOLD']&.to_i || BaseClinic::PHARMACY_TWEET_THRESHOLD
    TWEET_INCREASE_NEEDED = ENV['PHARMACY_TWEET_INCREASE_NEEDED']&.to_i || BaseClinic::PHARMACY_TWEET_INCREASE_NEEDED
    TWEET_COOLDOWN = ENV['PHARMACY_TWEET_COOLDOWN']&.to_i || BaseClinic::TWEET_COOLDOWN

    def initialize(storage, brand, stores)
      super(storage)
      @brand = brand
      @stores = stores
    end

    def cities
      @stores.map { |store| store['city'] }.compact.uniq.sort
    end

    def title
      @brand
    end

    def appointments
      cities.length
    end

    def storage_key
      "#{LAST_SEEN_STORAGE_PREFIX}:#{@brand}"
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

    def link
      @stores.detect { |s| s['url'] }['url']
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
