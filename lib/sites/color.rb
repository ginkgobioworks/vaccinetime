require 'date'
require 'json'
require 'open-uri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Color
  BASE_URL = 'https://home.color.com/api/v1'.freeze
  TOKEN_URL = "#{BASE_URL}/get_onsite_claim".freeze
  APPOINTMENT_URL = "#{BASE_URL}/vaccination_appointments/availability".freeze
  SITES = {
    'natickmall' => 'Natick Mall',
    'reggielewis' => 'Reggie Lewis Center',
    'gillettestadium' => 'Gillette Stadium',
    'fenway-hynes' => 'Fenway Park/Hynes Convention Center',
  }.freeze

  def self.all_clinics(storage, logger)
    SITES.flat_map do |site_id, site_name|
      sleep(2)
      SentryHelper.catch_errors(logger, 'Color') do
        logger.info "[Color] Checking site #{site_name}"
        Page.new(site_id, site_name, storage, logger).clinics
      end
    end
  end

  class Page
    def initialize(site_id, site_name, storage, logger)
      @site_id = site_id
      @site_name = site_name
      token_response = JSON.parse(URI.parse("#{TOKEN_URL}?partner=#{site_id}").open.read)
      token = token_response['token']
      @site_info = token_response['population_settings']['collection_sites'][0]
      @json = JSON.parse(URI.parse("#{APPOINTMENT_URL}?claim_token=#{token}&collection_site=#{@site_info['name']}").open.read)
      @storage = storage
      @logger = logger
    end

    def appointments_by_date
      @json['results'].each_with_object(Hash.new(0)) do |window, h|
        date = DateTime.parse(window['start'])
        h["#{date.month}/#{date.day}/#{date.year}"] += window['remaining_spaces']
      end
    end

    def clinics
      appointments_by_date.map do |date, appointments|
        @logger.info "[Color] Site #{@site_name} on #{date}: found #{appointments} appointments" if appointments.positive?
        Clinic.new(@site_id, @site_info, @storage, date, appointments)
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :appointments, :date

    def initialize(site_id, site_info, storage, date, appointments)
      super(storage)
      @site_id = site_id
      @site_info = site_info
      @date = date
      @appointments = appointments
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

    def link
      "https://home.color.com/vaccine/register/#{@site_id}"
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

    def sign_up_page
      link
    end
  end
end
