require 'json'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Zocdoc
  GQL_URL = 'https://api.zocdoc.com/directory/v2/gql'.freeze
  GQL_QUERY = %{
    query providerLocationsAvailability($directoryId: String, $insurancePlanId: String, $isNewPatient: Boolean, $isReschedule: Boolean, $jumpAhead: Boolean, $firstAvailabilityMaxDays: Int, $numDays: Int, $procedureId: String, $providerLocationIds: [String], $searchRequestId: String, $startDate: String, $timeFilter: TimeFilter, $widget: Boolean) {
      providerLocations(ids: $providerLocationIds) {
        id
        ...availability
        __typename
      }
    }

    fragment availability on ProviderLocation {
      id
      provider {
        id
        monolithId
        __typename
      }
      location {
        id
        monolithId
        state
        phone
        __typename
      }
      availability(directoryId: $directoryId, insurancePlanId: $insurancePlanId, isNewPatient: $isNewPatient, isReschedule: $isReschedule, jumpAhead: $jumpAhead, firstAvailabilityMaxDays: $firstAvailabilityMaxDays, numDays: $numDays, procedureId: $procedureId, searchRequestId: $searchRequestId, startDate: $startDate, timeFilter: $timeFilter, widget: $widget) {
        times {
          date
          timeslots {
            isResource
            startTime
            __typename
          }
          __typename
        }
        firstAvailability {
          startTime
          __typename
        }
        showGovernmentInsuranceNotice
        timesgridId
        today
        __typename
      }
      __typename
    }
  }.freeze

  SITES = {
    'Tufts Medical Center Vaccine Site - Boston' => {
      sign_up_link: 'https://www.tuftsmcvaccine.org/',
      gql_variables: {
        directoryId: '1172',
        insurancePlanId: '-1',
        isNewPatient: false,
        numDays: 21,
        procedureId: '5243',
        providerLocationIds: [
          'pr_fSHH-Tyvm0SZvoK3pfH8tx|lo_EMLPse6C60qr6_M2rJmilx',
        ],
        widget: false,
      },
    },
  }.freeze

  def self.all_clinics(storage, logger)
    SITES.flat_map do |site_name, config|
      sleep(2)
      SentryHelper.catch_errors(logger, 'Zocdoc') do
        logger.info "[Zocdoc] Checking site #{site_name}"
        Page.new(storage, logger, site_name, config).clinics
      end
    end
  end

  class Page
    def initialize(storage, logger, site_name, config)
      @storage = storage
      @logger = logger
      @site_name = site_name
      @config = config
    end

    def graphql_response
      res = RestClient.post(
        GQL_URL,
        {
          operationName: 'providerLocationsAvailability',
          query: GQL_QUERY,
          variables: @config[:gql_variables],
        }.to_json,
        content_type: :json
      )
      JSON.parse(res)['data']
    end

    def clinics
      graphql_response['providerLocations'].flat_map do |location|
        location['availability']['times'].map do |time|
          date = time['date']
          appointments = time['timeslots'].length
          if appointments.positive?
            @logger.info "[Zocdoc] Site #{@site_name} on #{date}: found #{appointments} appointments"
          end
          Clinic.new(
            @storage,
            @site_name,
            @config[:sign_up_link],
            date,
            appointments
          )
        end
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :name, :link, :date, :appointments

    def initialize(storage, name, link, date, appointments)
      super(storage)
      @name = name
      @link = link
      @date = date
      @appointments = appointments
    end

    def title
      "#{name} on #{date}"
    end

    def sign_up_page
      link
    end
  end
end
