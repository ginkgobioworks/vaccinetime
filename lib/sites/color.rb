require 'date'
require 'json'
require 'rest-client'
require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Color
  BASE_URL = 'https://home.color.com/api/v1'.freeze
  TOKEN_URL = "#{BASE_URL}/get_onsite_claim".freeze
  APPOINTMENT_URL = "#{BASE_URL}/vaccination_appointments/availability".freeze

  class Page
    def initialize(storage, logger)
      @storage = storage
      @logger = logger
    end

    def get_appointments(token, name)
      JSON.parse(
        RestClient.get(
          APPOINTMENT_URL,
          params: {
            claim_token: token,
            collection_site: name,
          }
        )
      )
    end

    def get_token_response
      JSON.parse(
        RestClient.get(
          TOKEN_URL,
          params: {
            partner: site_id,
          }
        )
      )
    end

    def appointments_by_date(token, name)
      json = get_appointments(token, name)
      json['results'].each_with_object(Hash.new(0)) do |window, h|
        date = DateTime.parse(window['start'])
        h["#{date.month}/#{date.day}/#{date.year}"] += window['remaining_spaces']
      end
    end

    def clinics
      @logger.info "[Color] Checking site #{site_id}"
      token_response = get_token_response
      token = token_response['token']
      site_info = token_response['population_settings']['collection_sites'][0]

      appointments_by_date(token, site_info['name']).map do |date, appointments|
        @logger.info "[Color] Site #{site_id} on #{date}: found #{appointments} appointments" if appointments.positive?
        Clinic.new(@storage, site_id, site_info, date, appointments, link)
      end
    end

    def link
      "https://home.color.com/vaccine/register/#{site_id}"
    end
  end

  class Gillette < Page
    def site_id
      'gillettestadium'
    end
  end

  class Hynes < Page
    def site_id
      'fenway-hynes'
    end
  end

  class ReggieLewis < Page
    def site_id
      'reggielewis'
    end
  end

  class LawrenceGeneral < Page
    def site_id
      'lawrencegeneral'
    end
  end

  class WestSpringfield < Page
    def site_id
      'westspringfield'
    end
  end

  class CicCommunity
    class CommunityPage < Page
      attr_reader :link, :site_id, :site_name, :calendar

      def initialize(storage, logger, link, site_name, site_id, calendar)
        super(storage, logger)
        @link = link
        @site_name = site_name
        @site_id = site_id
        @calendar = calendar
      end

      def get_appointments(token, name)
        JSON.parse(
          RestClient.get(
            APPOINTMENT_URL,
            params: {
              claim_token: token,
              collection_site: name,
              calendar: calendar,
            }
          )
        )
      end

      def clinics
        @logger.info "[Color] Checking site #{site_name}"
        token_response = get_token_response
        token = token_response['token']
        site_info = token_response['population_settings']['collection_sites'][0]

        appointments_by_date(token, site_info['name']).map do |date, appointments|
          @logger.info "[Color] Site #{site_name} on #{date}: found #{appointments} appointments" if appointments.positive?
          Clinic.new(@storage, site_id, site_info, date, appointments, link, site_name: site_name, module_name: 'COLOR_COMMUNITY')
        end
      end
    end

    def initialize(storage, logger)
      @storage = storage
      @logger = logger
    end

    def clinics
      html = Nokogiri::HTML(RestClient.get('https://www.cic-health.com/popups').body)
      html.search('select.location-select option').flat_map do |option|
        next if option['value'] == '-1'

        sleep 1
        begin
          site_name = option.text.strip
          page_url = option['value']
          page = RestClient.get(page_url).body
          match = %r{"https://home\.color\.com/vaccine/register/([\w_-]+)\?calendar=([\d\w-]+)"}.match(page)
          next unless match

          CommunityPage.new(@storage, @logger, page_url, site_name, match[1], match[2]).clinics
        rescue RestClient::TooManyRequests
          @logger.warn("[Color] Too many requests for #{option['value']}")
          sleep 1
          nil
        end
      end.compact
    end
  end

  class Northampton < Page
    def site_id
      'northampton'
    end

    def get_calendar
      res = RestClient.get('https://northamptonma.gov/2219/Vaccine-Clinics').body
      %r{"https://home\.color\.com/vaccine/register/northampton\?calendar=([\d\w-]+)"}.match(res)[1]
    end

    def get_appointments(token, name)
      calendar = get_calendar
      unless calendar
        @logger.warn '[Color] No Northampton calendar ID found'
        return { 'results' => [] }
      end

      JSON.parse(
        RestClient.get(
          APPOINTMENT_URL,
          params: {
            claim_token: token,
            collection_site: name,
            calendar: calendar,
          }
        )
      )
    end

    def link
      'https://northamptonma.gov/2219/Vaccine-Clinics'
    end
  end

  SITES = [
    Gillette,
    Hynes,
    ReggieLewis,
    CicCommunity,
    LawrenceGeneral,
    Northampton,
    WestSpringfield,
  ].freeze

  def self.all_clinics(storage, logger)
    SITES.flat_map do |page_class|
      sleep(1)
      SentryHelper.catch_errors(logger, 'Color') do
        page = page_class.new(storage, logger)
        page.clinics
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :appointments, :date, :link, :module_name

    def initialize(storage, site_id, site_info, date, appointments, link, site_name: nil, module_name: 'COLOR')
      super(storage)
      @site_id = site_id
      @site_info = site_info
      @date = date
      @appointments = appointments
      @link = link
      @site_name = site_name
      @module_name = module_name
    end

    def name
      @site_name || @site_info['name']
    end

    def title
      "#{name} on #{date}"
    end

    def city
      @site_info['address']['city']
    end

    def address
      addr = @site_info['address']['line1']
      addr += @site_info['address']['line2'] unless @site_info['address']['line2'].empty?
      addr + ", #{@site_info['address']['city']} #{@site_info['address']['state']} #{@site_info['address']['postal_code']}"
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

    def twitter_text
      "#{appointments} appointments available at #{name} in #{city}, MA on #{date}. Check eligibility and sign up at #{sign_up_page}"
    end
  end
end
