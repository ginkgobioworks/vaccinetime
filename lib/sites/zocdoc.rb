require 'json'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Zocdoc
  GQL_URL = 'https://api.zocdoc.com/directory/v2/gql'.freeze
  GQL_QUERY = %{
    query VaccineTime($providers: [String]) {
      providers(ids: $providers) {
        id
        nameInSentence
        providerLocations {
          location {
            address1
            address2
            city
            state
            zipCode
          }
          availability(numDays: 28) {
            times {
              date
              timeslots {
                startTime
              }
            }
          }
        }
      }
    }
  }.freeze

  SITES = {
    'pr_fSHH-Tyvm0SZvoK3pfH8tx' => {
      name: 'Tufts MC Vaccine Site - Boston Location',
      sign_up_link: 'https://www.zocdoc.com/wl/tuftscovid19vaccination/patientvaccine',
    },
    'pr_BDBebslqJU2vrCAvVMhYeh' => {
      name: 'Holtzman Medical Group - Mount Ida Campus',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
    'pr_iXjD9x2P-0OrLNoIknFr8R' => {
      name: 'AFC Saugus',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
    'pr_TeD-JuoydUKqszEn2ATb8h' => {
      name: 'AFC New Bedford',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
    'pr_pEgrY3r5qEuYKsKvc4Kavx' => {
      name: 'AFC Worcester',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
    'pr_VUnpWUtg1k2WFBMK8IhZkx' => {
      name: 'AFC Dedham',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
    'pr_4Vg_3ZeLY0aHJJxsCU-WhB' => {
      name: 'AFC West Springfield',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
    'pr_CUmBnwtlz0C16bif5EU0IR' => {
      name: 'AFC Springfield',
      sign_up_link: 'https://www.zocdoc.com/vaccine/screener?state=MA',
    },
  }.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Zocdoc] Checking site'
    SentryHelper.catch_errors(logger, 'Zocdoc') do
      fetch_graphql['providers'].flat_map do |provider|
        Page.new(storage, logger, provider).clinics
      end
    end
  end

  def self.fetch_graphql
    res = RestClient.post(
      GQL_URL,
      {
        operationName: 'VaccineTime',
        query: GQL_QUERY,
        variables: { providers: SITES.keys },
      }.to_json,
      content_type: :json
    )
    JSON.parse(res)['data']
  end

  class Page
    def initialize(storage, logger, provider)
      @storage = storage
      @logger = logger
      @provider = provider
    end

    def name
      @provider['nameInSentence']
    end

    def sign_up_link
      SITES[@provider['id']][:sign_up_link]
    end

    def clinics
      @provider['providerLocations'].flat_map do |location|
        (location.dig('availability', 'times') || []).map do |time|
          date = time['date']
          appointments = time['timeslots'].length
          if appointments.positive?
            @logger.info "[Zocdoc] Site #{name} on #{date}: found #{appointments} appointments"
          end
          Clinic.new(
            @storage,
            name,
            sign_up_link,
            date,
            appointments,
            location['location']
          )
        end
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :name, :link, :date, :appointments

    def initialize(storage, name, link, date, appointments, location)
      super(storage)
      @name = name
      @link = link
      @date = date
      @appointments = appointments
      @location = location
    end

    def city
      @location['city']
    end

    def address
      addr = @location['address1']
      addr += " #{@location['address2']}" unless @location['address2'].empty?
      addr + ", #{@location['city']} #{@location['state']} #{@location['zipCode']}"
    end

    def title
      "#{name} in #{city}, MA on #{date}"
    end

    def sign_up_page
      link
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Available appointments:* #{render_slack_appointments}\n*Link:* #{link}",
        },
      }
    end
  end
end
