require 'json'
require 'date'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module HolyokeHealth
  GQL_URL = 'https://api.blockitnow.com/graphql'.freeze
  SPECIALTY_ID = 'bf21b91b-f6f9-4a78-aca4-dbdedbe23a75'.freeze
  PROCEDURE_ID = '468129ce-1d13-4114-92aa-78e2a3b04da5'.freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'HolyokeHealth') do
      locations.flat_map do |location|
        fetch_appointments(location['id']).each_with_object(Hash.new(0)) do |appt, h|
          h[Date.parse(appt['start']).to_s] += 1
        end.map do |date, appts|
          Clinic.new(storage, location['location'], date, appts)
        end
      end
    end
  end

  def self.organization_id
    JSON.parse(
      RestClient.post(
        GQL_URL,
        {
          operationName: 'GetConsumerSchedulingOrganizationQuery',
          query: %{
            query GetConsumerSchedulingOrganizationQuery($id: ID!) {
              getConsumerSchedulingOrganization(id: $id) {
                id
                name
              }
            }
          },
          variables: { id: 'covid-holyoke' },
        }.to_json,
        content_type: :json
      ).body
    )['data']['getConsumerSchedulingOrganization']['id']
  end

  def self.locations
    JSON.parse(
      RestClient.post(
        GQL_URL,
        {
          operationName: 'SearchProfilesInOrganizationQuery',
          query: %{
            query SearchProfilesInOrganizationQuery(
              $organizationId: ID!
              $page: Int
              $pageSize: Int
              $searchProfilesInput: SearchProfilesInput!
            ) {
              searchProfilesInOrganization(
                organizationId: $organizationId
                page: $page
                pageSize: $pageSize
                searchProfilesInput: $searchProfilesInput
              ) {
                id
                location {
                  id
                  name
                  address1
                  address2
                  city
                  state
                  postalCode
                }
              }
            }
          },
          variables: {
            organizationId: organization_id,
            page: 1,
            pageSize: 10,
            searchProfilesInput: {
              hasConsumerScheduling: true,
              isActive: true,
              organizationIsActive: true,
              procedureId: PROCEDURE_ID,
              sort: 'NEXT_AVAILABILITY',
              specialtyId: SPECIALTY_ID,
            },
          },
        }.to_json,
        content_type: :json
      ).body
    )['data']['searchProfilesInOrganization']
  end

  def self.fetch_appointments(profile_id)
    res = JSON.parse(
      RestClient.post(
        GQL_URL,
        {
          operationName: 'GetConsumerSchedulingProfileSlotsQuery',
          query: %{
            query GetConsumerSchedulingProfileSlotsQuery(
              $procedureId: ID!
              $profileId: ID!
              $start: String
              $end: String
            ) {
              getConsumerSchedulingProfileSlots(
                procedureId: $procedureId
                profileId: $profileId
                start: $start
                end: $end
              ) {
                id
                start
                end
                status
                slotIdsForAppointment
                __typename
              }
            }
          },
          variables: {
            procedureId: PROCEDURE_ID,
            profileId: profile_id,
            start: Date.today.strftime('%Y-%m-%d'),
            end: (Date.today + 28).strftime('%Y-%m-%d'),
          },
        }.to_json,
        content_type: :json
      ).body
    )['data']['getConsumerSchedulingProfileSlots']
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments

    def initialize(storage, location_data, date, appointments)
      super(storage)
      @location_data = location_data
      @date = date
      @appointments = appointments
    end

    def module_name
      'HOLYOKE_HEALTH'
    end

    def title
      "#{location} on #{date}"
    end

    def location
      @location_data['name']
    end

    def city
      @location_data['city']
    end

    def link
      'https://app.blockitnow.com/consumer/covid-holyoke/search?specialtyId=bf21b91b-f6f9-4a78-aca4-dbdedbe23a75&procedureId=468129ce-1d13-4114-92aa-78e2a3b04da5'
    end

    def twitter_text
      "#{appointments} appointments available at #{title} in #{city}, MA. Check eligibility and sign up at #{sign_up_page}"
    end
  end
end
