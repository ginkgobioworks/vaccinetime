require 'rest-client'
require 'json'

require_relative '../sentry_helper'
require_relative './pharmacy_clinic'

module Vaccinespotter
  API_URL = 'https://www.vaccinespotter.org/api/v0/states/MA.json'.freeze
  IGNORE_BRANDS = ['CVS', 'Costco', 'Hannaford', 'PrepMod'].freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Vaccinespotter') do
      logger.info '[Vaccinespotter] Checking site'
      ma_stores.flat_map do |brand, stores|
        if stores.all? { |store| store['appointments'].length.positive? }
          link = stores.detect { |s| s['url'] }['url']
          group_stores_by_date(stores).map do |date, appts|
            logger.info "[Vaccinespotter] Found #{appts.keys.length} #{brand} stores with #{appts.values.sum} appointments on #{date}"
            ClinicWithAppointments.new(storage, brand, date, appts, link)
          end
        else
          logger.info "[Vaccinespotter] Found #{stores.length} #{brand} stores with appointments"
          Clinic.new(storage, brand, stores)
        end
      end
    end
  end

  def self.group_stores_by_date(stores)
    stores.each_with_object({}) do |store, h|
      store['appointments'].reject { |appt| appt['type']&.include?('2nd Dose Only') }.each do |appt|
        date = Date.parse(appt['time'])
        h[date] ||= Hash.new(0)
        h[date][store['city']] += 1
      end
    end
  end

  def self.ma_stores
    ma_data['features'].each_with_object({}) do |feature, h|
      properties = feature['properties']
      next unless properties

      brand = get_brand(properties['provider_brand_name'])
      appointments_available = properties['appointments_available_all_doses']
      next unless brand && appointments_available && !IGNORE_BRANDS.include?(brand)

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

  class Clinic < PharmacyClinic
    LAST_SEEN_STORAGE_PREFIX = 'vaccinespotter-last-cities'.freeze

    def initialize(storage, brand, stores)
      super(storage)
      @brand = brand
      @stores = stores
    end

    def module_name
      'VACCINESPOTTER_PHARMACY'
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
    attr_reader :date, :link

    def initialize(storage, brand, date, appts, link)
      super(storage)
      @brand = brand
      @date = date
      @appts_by_store = appts
      @link = link
    end

    def module_name
      'VACCINESPOTTER'
    end

    def title
      "#{@brand} on #{@date}"
    end

    def cities
      @appts_by_store.keys.sort
    end

    def appointments
      @appts_by_store.values.sum
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Available appointments in:* #{cities.join(', ')}\n*Date:* #{@date}\n*Number of appointments:* #{appointments}\n*Link:* #{link}",
        },
      }
    end

    def twitter_text
      date_text = @date.strftime('%-m/%d')
      tweet_groups = []

      #   x chars: NUM_APPOINTMENTS
      #  27 chars: " appointments available at "
      #   y chars: BRAND
      #   4 chars: " on "
      #   z chars: DATE
      #   4 chars: " in "
      #   w chars: STORES
      #  35 chars: ". Check eligibility and sign up at "
      #  23 chars: shortened link
      # ---------
      # 280 chars total, 280 is the maximum
      text_limit = 280 - (27 + @brand.length + 4 + date_text.length + 4 + 35 + 23)

      tweet_stores = cities.dup
      first_city = tweet_stores.shift
      cities_text = first_city
      group_appointments = @appts_by_store[first_city]

      while (city = tweet_stores.shift)
        pending_appts = group_appointments + @appts_by_store[city]
        pending_text = ", #{city}"
        if pending_appts.to_s.length + cities_text.length + pending_text.length > text_limit
          tweet_groups << { cities_text: cities_text, group_appointments: group_appointments }
          cities_text = city
          group_appointments = @appts_by_store[city]
        else
          cities_text += pending_text
          group_appointments = pending_appts
        end
      end
      tweet_groups << { cities_text: cities_text, group_appointments: group_appointments }

      tweet_groups.map do |group|
        "#{group[:group_appointments]} appointments available at #{@brand} on #{date_text} in #{group[:cities_text]}. Check eligibility and sign up at #{sign_up_page}"
      end
    end
  end
end
