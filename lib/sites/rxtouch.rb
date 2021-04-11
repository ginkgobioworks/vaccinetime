require 'rest-client'
require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Rxtouch
  class Page
    def initialize(storage, logger)
      @storage = storage
      @logger = logger
    end

    def clinics
      @logger.info "[Rxtouch] Checking #{name}"
      cities = Set.new
      success, cookies = fetch_cookies
      unless success
        @logger.info "[Rxtouch] #{cookies}"
        return []
      end

      zip_codes.keys.each_with_index do |zip, idx|
        result = fetch_zip(zip, cookies)
        if result.include?('loggedout')
          success, cookies = fetch_cookies
          unless success
            @logger.info "[Rxtouch] #{cookies}"
            break
          end
          result = fetch_zip(zip, cookies)
        end

        next if result.include?('There are no locations with available appointments')
        next unless result.empty?

        cities.merge(fetch_facilities(zip, cookies))
      end

      @logger.info "[Rxtouch] Found #{name} appointments in #{cities.join(', ')}" if cities.any?
      Clinic.new(@storage, name, cities.to_a, sign_up_url)
    end

    def fetch_cookies
      cookies = {}
      12.times do
        res = RestClient.get(sign_up_url, cookies: cookies)
        cookies = res.cookies
        return [true, cookies] unless res.request.url.include?('queue-it.net')

        sleep 5
      end

      [false, "Couldn't get through queue"]
    end

    def fetch_zip(zip, cookies)
      JSON.parse(
        RestClient.post(
          api_url,
          {
            zip: zip,
            appointmentType: appointment_type,
            PatientInterfaceMode: '0',
          },
          cookies: cookies
        ).body
      )
    end

    def fetch_facilities(zip, cookies)
      html = Nokogiri::HTML(
        RestClient.get(
          "#{base_url}/Schedule?zip=#{zip}&appointmentType=#{appointment_type}",
          cookies: cookies
        ).body
      )
      html.search('select#facility option').map do |facility|
        city = /Pharmacy #\d+ - ([^-]+) -/.match(facility.text)
        city[1] if city
      end.compact
    end

    def sign_up_url
      "#{base_url}/Advisory"
    end
  end

  class StopAndShop < Page
    def name
      'Stop & Shop'
    end

    def appointment_type
      '5957'
    end

    def base_url
      'https://stopandshopsched.rxtouch.com/rbssched/program/covid19/Patient'
    end

    def api_url
      "#{base_url}/CheckZipCode"
    end

    def zip_codes
      {
        '01913' => 'Amesbury',
        '02721' => 'Fall River',
        '01030' => 'Feeding Hills',
        '02338' => 'Halifax',
        '02645' => 'Harwich',
        '02601' => 'Hyannis',
        '01904' => 'Lynn',
        '01247' => 'North Adams',
        '02653' => 'Orleans',
        '01201' => 'Pittsfield',
        '01907' => 'Swampscott',
        '01089' => 'West Springfield',
        '01801' => 'Woburn',
      }
    end
  end

  class Hannaford < Page
    def name
      'Hannaford'
    end

    def appointment_type
      '5954'
    end

    def base_url
      'https://hannafordsched.rxtouch.com/rbssched/program/covid19/Patient'
    end

    def api_url
      "#{base_url}/CheckZipCode"
    end

    def zip_codes
      {
        '01002' => 'Amherst',
        '02189' => 'Weymouth',
      }
    end
  end

  class Clinic < BaseClinic
    LAST_SEEN_STORAGE_PREFIX = 'rxtouch-last-cities'.freeze
    TWEET_THRESHOLD = ENV['PHARMACY_TWEET_THRESHOLD']&.to_i || BaseClinic::PHARMACY_TWEET_THRESHOLD
    TWEET_INCREASE_NEEDED = ENV['PHARMACY_TWEET_INCREASE_NEEDED']&.to_i || BaseClinic::PHARMACY_TWEET_INCREASE_NEEDED
    TWEET_COOLDOWN = ENV['PHARMACY_TWEET_COOLDOWN']&.to_i || BaseClinic::TWEET_COOLDOWN

    attr_reader :cities, :link

    def initialize(storage, brand, cities, link)
      super(storage)
      @brand = brand
      @cities = cities
      @link = link
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

  ALL_SITES = [
    #StopAndShop,
    Hannaford,
  ].freeze

  def self.all_clinics(storage, logger)
    ALL_SITES.flat_map do |site_class|
      SentryHelper.catch_errors(logger, 'Rxtouch') do
        page = site_class.new(storage, logger)
        page.clinics
      end
    end
  end
end
