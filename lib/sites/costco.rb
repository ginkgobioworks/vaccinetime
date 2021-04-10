require 'rest-client'
require 'json'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Costco
  BASE_API_URL = 'https://book.appointment-plus.com/book-appointment'.freeze
  LOCATION_URL = "#{BASE_API_URL}/get-clients".freeze
  EMPLOYEE_URL = "#{BASE_API_URL}/get-employees".freeze
  SERVICES_URL = "#{BASE_API_URL}/get-services".freeze
  APPOINTMENT_URL = "#{BASE_API_URL}/get-grid-hours".freeze

  def self.all_clinics(storage, logger)
    logger.info '[Costco] Checking site'

    SentryHelper.catch_errors(logger, 'Costco') do
      cities = get_locations['clientObjects'].filter do |client|
        client['state'] == 'MA' &&
          client['displayToCustomer'] == true &&
          has_appointments?(client['id'], client['clientMasterId'])
      end.map do |client|
        client['locationName'].gsub('Costco', '').strip
      end.sort

      logger.info "[Costco] Found appointments in #{cities.join(', ')}" if cities.any?
      [Clinic.new(storage, cities)]
    end
  end

  def self.has_appointments?(client_id, client_master_id)
    employees = get_employees(client_id, client_master_id)
    return false unless employees['employeeObjects'].any?

    employee_id = employees['employeeObjects'][0]['id']
    services = get_services(client_id, client_master_id, employee_id)
    return false unless services.any?

    appointments = get_appointments(client_master_id, employee_id, services)
    appointments['data']['gridHours'].any?
  end

  def self.get_locations
    JSON.parse(
      RestClient.get(
        LOCATION_URL,
        params: {
          clientMasterId: 426227,
          pageNumber: 1,
          itemsPerPage: 10,
          keyword: '01545',
          clientId: '',
          employeeId: '',
          'centerCoordinates[id]' => 528587,
          'centerCoordinates[latitude]' => 42.283459,
          'centerCoordinates[longitude]' => -71.726662,
          'centerCoordinates[accuracy]' => '',
          'centerCoordinates[whenAdded]' => '2021-04-10 11:09:11',
          'centerCoordinates[searchQuery]' => '01545',
          radiusInKilometers: 100,
          '_' => Time.now.to_i
        }
      ).body
    )
  end

  def self.get_employees(client_id, client_master_id)
    JSON.parse(
      RestClient.get(
        EMPLOYEE_URL,
        params: {
          clientMasterId: client_master_id,
          clientId: client_id,
          pageNumber: 1,
          itemsPerPage: 10,
          keyword: '',
          employeeObjects: '',
          '_' => Time.now.to_i
        }
      ).body
    )
  end

  def self.get_services(client_id, client_master_id, employee_id)
    JSON.parse(
      RestClient.get(
        "#{SERVICES_URL}/#{employee_id}",
        params: {
          clientMasterId: client_master_id,
          clientId: client_id,
          pageNumber: 1,
          itemsPerPage: 10,
          keyword: '',
          serviceId: '',
          '_' => Time.now.to_i,
        }
      ).body
    )['serviceObjects'].map { |service| service['id'] }
  end

  def self.get_appointments(client_master_id, employee_id, services)
    JSON.parse(
      RestClient.get(
        APPOINTMENT_URL,
        params: {
          startTimestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          endTimestamp: (Date.today + 28).strftime('%Y-%m-%d %H:%M:%S'),
          limitNumberOfDaysWithOpenSlots: 5,
          employeeId: employee_id,
          services: services,
          numberOfSpotsNeeded: 1,
          isStoreHours: true,
          clientMasterId: client_master_id,
          toTimeZone: false,
          fromTimeZone: 149,
          '_' => Time.now.to_i
        }
      ).body
    )
  end

  class Clinic < BaseClinic
    LAST_SEEN_STORAGE_PREFIX = 'costco-last-cities'.freeze
    TWEET_THRESHOLD = ENV['PHARMACY_TWEET_THRESHOLD']&.to_i || BaseClinic::PHARMACY_TWEET_THRESHOLD
    TWEET_INCREASE_NEEDED = ENV['PHARMACY_TWEET_INCREASE_NEEDED']&.to_i || BaseClinic::PHARMACY_TWEET_INCREASE_NEEDED
    TWEET_COOLDOWN = ENV['PHARMACY_TWEET_COOLDOWN']&.to_i || BaseClinic::TWEET_COOLDOWN

    attr_reader :cities

    def initialize(storage, cities)
      super(storage)
      @cities = cities
    end

    def title
      'Costco'
    end

    def link
      'https://book.appointment-plus.com/d133yng2'
    end

    def appointments
      cities.length
    end

    def storage_key
      "#{LAST_SEEN_STORAGE_PREFIX}:Costco"
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
