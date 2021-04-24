require 'json'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Southcoast
  SIGN_UP_URL = 'https://www.southcoast.org/covid-19-vaccine-scheduling/'.freeze
  API_URL = 'https://southcoastapps.southcoast.org/OnlineAppointmentSchedulingApi/api/resourceTypes/slots/search'.freeze
  TOKEN_URL = 'https://southcoastapps.southcoast.org/OnlineAppointmentSchedulingApi/api/sessions'.freeze

  SITES = [
    'Fall River',
    'North Dartmouth',
    'Wareham',
  ]

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Southcoast') do
      main_page = RestClient.get(SIGN_UP_URL)
      if /At this time, there are no appointments available through online scheduling./ =~ main_page.body
        logger.info '[Southcoast] No sign ups available'
        return []
      end
    end

    SITES.flat_map do |site|
      sleep(2)
      SentryHelper.catch_errors(logger, 'Southcoast') do
        logger.info "[Southcoast] Checking site #{site}"
        Page.new(storage, logger, site).clinics
      end
    end
  end

  class Page
    def initialize(storage, logger, site)
      @storage = storage
      @logger = logger
      @site = site
    end

    def clinics
      json_data['dateToSlots'].each_with_object(Hash.new(0)) do |(date, slots), h|
        slots.each do |_department, slot|
          h[date] += slot['slots'].length
        end
      end.map do |date, appointments|
        if appointments.positive?
          @logger.info "[Southcoast] Site #{@site} found #{appointments} appointments on #{date}"
        end
        Clinic.new(@storage, @site, date, appointments)
      end
    end

    def json_data
      payload = {
        ProviderCriteria: {
          SpecialtyID: nil,
          ConcentrationID: nil,
        },
        ResourceTypeId: '98C5A8BE-25D1-4125-9AD5-1EE64AD164D2',
        StartDate: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
        EndDate: (DateTime.now + 28).to_time.utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
        Location: @site,
      }
      res = RestClient.post(
        API_URL,
        payload.to_json,
        content_type: :json,
        SessionToken: token,
        Origin: 'https://www.southcoast.org',
        Referer: 'https://www.southcoast.org/covid-19-vaccine-scheduling/'
      )
      JSON.parse(res.body)
    end

    def token
      JSON.parse(RestClient.get(TOKEN_URL).body)
    end
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments

    def initialize(storage, site, date, appointments)
      super(storage)
      @site = site
      @date = date
      @appointments = appointments
    end

    def module_name
      'SOUTHCOAST'
    end

    def title
      "Southcoast Health in #{@site}, MA on #{date}"
    end

    def link
      SIGN_UP_URL
    end
  end
end
