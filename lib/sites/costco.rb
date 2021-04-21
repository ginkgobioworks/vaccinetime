require 'rest-client'
require 'json'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Costco
  BASE_API_URL = 'https://book-costcopharmacy.appointment-plus.com'.freeze
  BOOKING_ID = 'd133yng2'.freeze
  PREFERENCES_URL = "#{BASE_API_URL}/get-preferences".freeze
  LOCATION_URL = "#{BASE_API_URL}/book-appointment/get-clients".freeze
  EMPLOYEE_URL = "#{BASE_API_URL}/book-appointment/get-employees".freeze
  SERVICES_URL = "#{BASE_API_URL}/book-appointment/get-services".freeze
  APPOINTMENT_URL = "#{BASE_API_URL}/book-appointment/get-grid-hours".freeze

  def self.all_clinics(storage, logger)
    logger.info '[Costco] Checking site'

    SentryHelper.catch_errors(logger, 'Costco') do
      appointments = get_locations['clientObjects'].filter do |client|
        client['displayToCustomer'] == true
      end.map do |client|
        {
          location: client['locationName'].gsub('Costco', '').strip,
          appointments: get_city_appointments(client['id'], client['clientMasterId']),
        }
      end.filter do |client|
        client[:appointments].positive?
      end

      logger.info "[Costco] Found #{appointments.map { |a| a[:appointments] }.sum} appointments in #{appointments.map { |a| a[:location] }.join(', ')}" if appointments.any?
      [Clinic.new(storage, appointments)]
    end
  end

  def self.get_city_appointments(client_id, client_master_id)
    employees = get_employees(client_id, client_master_id)
    return 0 unless employees['employeeObjects'].any?

    employee_id = employees['employeeObjects'][0]['id']
    services = get_services(client_id, client_master_id, employee_id)
    return 0 unless services.any?

    appointments = get_appointments(client_master_id, employee_id, services)
    appointments['data']['gridHours'].map do |_date, obj|
      obj['timeSlots']['numberOfSpots'].zip(obj['timeSlots']['numberOfSpotsTaken']).map { |a, b| a - b }.sum
    end.sum
  end

  def self.get_master_id
    JSON.parse(
      RestClient.get(
        PREFERENCES_URL,
        params: {
          clientMasterId: '',
          clientId: '',
          bookingId: BOOKING_ID,
          '_' => Time.now.to_i,
        }
      ).body
    )['data']['clientmasterId']
  end

  def self.get_locations
    JSON.parse(
      RestClient.get(
        LOCATION_URL,
        params: {
          clientMasterId: get_master_id,
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
    def initialize(storage, appointment_data)
      super(storage)
      @appointment_data = appointment_data.sort_by { |client| client[:location] }
    end

    def title
      'Costco'
    end

    def link
      'https://www.costco.com/covid-vaccine.html'
    end

    def appointments
      @appointment_data.map { |a| a[:appointments] }.sum
    end

    def cities
      @appointment_data.map { |a| a[:location] }
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

      tweet_stores = @appointment_data.dup
      first_store = tweet_stores.shift
      cities_text = first_store[:location]
      group_appointments = first_store[:appointments]

      while (store = tweet_stores.shift)
        pending_appts = group_appointments + store[:appointments]
        pending_text = ", #{store[:location]}"
        if pending_appts.to_s.length + cities_text.length + pending_text.length > text_limit
          tweet_groups << { cities_text: cities_text, group_appointments: group_appointments }
          cities_text = store[:location]
          group_appointments = store[:appointments]
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
