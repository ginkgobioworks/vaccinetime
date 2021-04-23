require 'rest-client'
require 'json'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Vaccinespotter
  API_URL = 'https://www.vaccinespotter.org/api/v0/states/MA.json'.freeze
  IGNORE_BRANDS = ['cvs', 'costco', 'hannaford', 'maimmunizations'].freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Vaccinespotter') do
      logger.info '[Vaccinespotter] Checking site'
      ma_stores.map do |brand, stores|
        if stores.all? { |store| store['appointments'].length.positive? }
          logger.info "[Vaccinespotter] Found #{stores.length} #{brand} stores with #{stores.map { |s| first_appointments(s) }.sum} appointments"
          ClinicWithAppointments.new(storage, brand, stores)
        else
          logger.info "[Vaccinespotter] Found #{stores.length} #{brand} stores with appointments"
          Clinic.new(storage, brand, stores)
        end
      end
    end
  end

  def self.first_appointments(store)
    store['appointments'].reject { |appt| appt['type']&.include?('2nd Dose Only') }.length
  end

  def self.ma_stores
    ma_data['features'].each_with_object({}) do |feature, h|
      properties = feature['properties']
      next unless properties && properties['provider']

      next if IGNORE_BRANDS.include?(properties['provider'])

      brand = get_brand(properties['provider_brand_name'])
      appointments_available = properties['appointments_available_all_doses']
      next unless brand && appointments_available

      h[brand] ||= []
      h[brand] << properties
    end
  end

  def self.get_brand(brand_name)
    if ['Price Chopper', 'Market 32'].include?(brand_name)
      'Price Chopper/Market 32'
    else
      brand_name
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

  class ClinicWithAppointments < BaseClinic
    def initialize(storage, brand, stores)
      super(storage)
      @brand = brand
      @stores = stores.sort_by { |store| store['city'] }
    end

    def title
      @brand
    end

    def cities
      @stores.map { |store| store['city'] }.compact.uniq
    end

    def stores_with_appointments
      @stores.filter { |s| first_appointments(s).positive? }
    end

    def appointments
      @stores.map { |s| first_appointments(s) }.sum
    end

    def first_appointments(store)
      Vaccinespotter.first_appointments(store)
    end

    def link
      @stores.detect { |s| s['url'] }['url']
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Available appointments in:* #{cities.join(', ')}\n*Number of appointments:* #{appointments}\n*Link:* #{link}",
        },
      }
    end

    def twitter_text
      tweet_groups = []

      #   x chars: NUM_APPOINTMENTS
      #   1 chars: " "
      #   y chars: BRAND
      #  27 chars: " appointments available in "
      #   z chars: STORES
      #  35 chars: ". Check eligibility and sign up at "
      #  23 chars: shortened link
      # ---------
      # 280 chars total, 280 is the maximum
      text_limit = 280 - (1 + title.length + 27 + 35 + 23)

      tweet_stores = stores_with_appointments
      first_store = tweet_stores.shift
      cities_text = first_store['city']
      group_appointments = first_appointments(first_store)

      while (store = tweet_stores.shift)
        pending_appts = group_appointments + first_appointments(store)
        pending_text = ", #{store['city']}"
        if pending_appts.to_s.length + cities_text.length + pending_text.length > text_limit
          tweet_groups << { cities_text: cities_text, group_appointments: group_appointments }
          cities_text = store['city']
          group_appointments = first_appointments(store)
        else
          cities_text += pending_text
          group_appointments = pending_appts
        end
      end
      tweet_groups << { cities_text: cities_text, group_appointments: group_appointments }

      tweet_groups.map do |group|
        "#{group[:group_appointments]} #{title} appointments available in #{group[:cities_text]}. Check eligibility and sign up at #{sign_up_page}"
      end
    end
  end
end
