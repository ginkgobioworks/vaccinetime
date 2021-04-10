require 'date'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Athena
  GQL_URL = 'https://framework-backend.scheduling.athena.io/v1/graphql'.freeze
  GQL_QUERY = %{
    query SearchSlots(
      $locationIds: [String!]
      $practitionerIds: [String!]
      $specialty: String
      $serviceTypeTokens: [String!]!
      $startAfter: String!
      $startBefore: String!
      $visitType: VisitType
    ) {
      searchSlots(
        locationIds: $locationIds
        practitionerIds: $practitionerIds
        specialty: $specialty
        serviceTypeTokens: $serviceTypeTokens
        startAfter: $startAfter
        startBefore: $startBefore
        visitType: $visitType
      ) {
        location {
          reference
          resource {
            ... on Location {
              id
              name
              address {
                line
                city
                state
                postalCode
                __typename
              }
              telecom {
                system
                value
                __typename
              }
              timezone
              managingOrganization {
                reference
                __typename
              }
              __typename
            }
            __typename
          }
          __typename
        }
        practitionerAvailability {
          isTelehealth
          practitioner {
            reference
            resource {
              ... on Practitioner {
                id
                name {
                  text
                  __typename
                }
                __typename
              }
              __typename
            }
            __typename
          }
          availability {
            id
            start
            end
            status
            serviceType {
              text
              coding {
                code
                system
                __typename
              }
              __typename
            }
            schedulingListToken
            __typename
          }
          __typename
        }
        __typename
      }
    }
  }.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Athena] Checking site'

    SentryHelper.catch_errors(logger, 'Athena') do
      fetch_availability['data']['searchSlots'].each_with_object({}) do |slot, h|
        location = slot['location']['resource']['name']
        h[location] ||= Hash.new(0)
        slot['practitionerAvailability'].each do |practitioner|
          practitioner['availability'].each do |availability|
            date = Date.parse(availability['start']).to_s
            h[location][date] += 1
          end
        end
      end.flat_map do |location, dates|
        dates.map do |date, appointments|
          logger.info "[Athena] Found #{appointments} appointments on #{date}"
          Clinic.new(storage, location, date, appointments)
        end
      end
    end
  end

  def self.token
    JSON.parse(
      RestClient.get('https://framework-backend.scheduling.athena.io/t').body
    )['token']
  end

  def self.jwt
    JSON.parse(
      RestClient.get('https://framework-backend.scheduling.athena.io/u?locationId=2804-102&practitionerId=&contextId=2804').body
    )['token']
  end

  def self.fetch_availability
    variables = {
      locationIds: ['2804-102'],
      practitionerIds: [],
      serviceTypeTokens: ['codesystem.scheduling.athena.io/servicetype.canonical|49b8e757-0345-4923-9889-a3b57f05aed2'],
      specialty: 'Unknown Provider',
      startAfter: Time.now.strftime('%Y-%m-%dT%H:%M:00-04:00'),
      startBefore: (Date.today + 28).strftime('%Y-%m-%dT23:59:59-04:00'),
    }

    JSON.parse(
      RestClient.post(
        GQL_URL,
        {
          operationName: 'SearchSlots',
          query: GQL_QUERY,
          variables: variables,
        }.to_json,
        content_type: :json,
        authorization: "Bearer #{token}",
        'x-scheduling-jwt' => jwt
      ).body
    )
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments

    def initialize(storage, location, date, appointments)
      super(storage)
      @location = location
      @date = date
      @appointments = appointments
    end

    def title
      "#{@location} on #{date}"
    end

    def link
      'https://consumer.scheduling.athena.io/?departmentId=2804-102'
    end
  end
end
