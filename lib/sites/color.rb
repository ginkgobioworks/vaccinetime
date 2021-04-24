require 'date'
require 'json'
require 'rest-client'

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
    attr_reader :appointments, :date, :link

    def initialize(storage, site_id, site_info, date, appointments, link)
      super(storage)
      @site_id = site_id
      @site_info = site_info
      @date = date
      @appointments = appointments
      @link = link
    end

    def module_name
      'COLOR'
    end

    def name
      @site_info['name']
    end

    def title
      "#{name} on #{date}"
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
  end
end
