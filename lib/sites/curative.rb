require 'date'
require 'json'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Curative
  BASE_URL = 'https://curative.com/sites/'.freeze
  API_URL = 'https://labtools.curativeinc.com/api/v1/testing_sites/'.freeze
  SITES = {
    24181 => 'DoubleTree Hotel - Danvers',
    24182 => 'Eastfield Mall - Springfield',
    25336 => 'Circuit City - Dartmouth',
  }.freeze

  def self.all_clinics(storage, logger)
    SITES.flat_map do |site_num, site_name|
      sleep(2)
      SentryHelper.catch_errors(logger, 'Curative') do
        logger.info "[Curative] Checking site #{site_num}: #{site_name}"
        Page.new(site_num, storage, logger).clinics
      end
    end
  end

  class Page
    SIGN_UP_SEEN_KEY = 'vaccine-curative-sign-up-date'.freeze
    QUEUE_SITE = 'https://curative.queue-it.net'.freeze

    attr_reader :json

    def initialize(site_num, storage, logger)
      @site_num = site_num
      @json = JSON.parse(RestClient.get(API_URL + site_num.to_s).body)
      @storage = storage
      @logger = logger
    end

    def clinics
      return [] unless appointments_are_visible?

      appointments_by_date.map do |k, v|
        @logger.info "[Curative] Site #{@site_num} on #{k}: found #{v} appoinments" if v.positive?
        Clinic.new(@site_num, @json, @storage, k, v)
      end
    end

    def appointments_are_visible?
      now = Time.now
      if ENV['ENVIRONMENT'] == 'production' && !(Date.today.thursday? && now.hour >= 8 && now.min >= 30)
        @logger.info "[Curative] Site #{@site_num} is not Thursday after 8:30"
        return false
      end

      if @json['invitation_required_for_public_booking'] == true
        @logger.info "[Curative] Site #{@site_num} requires invitation"
        return false
      end

      base_site = RestClient.get(BASE_URL + @site_num.to_s)
      if base_site.request.url.start_with?("#{QUEUE_SITE}/afterevent")
        @logger.info "[Curative] Site #{@site_num} event has ended"
        return false
      end

      true
    end

    def appointments_by_date
      @json['appointment_windows'].each_with_object(Hash.new(0)) do |window, h|
        date = DateTime.parse(window['start_time'])
        h["#{date.month}/#{date.day}/#{date.year}"] +=
          if window['status'] == 'Active'
            window['public_slots_available']
          else
            0
          end
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :appointments, :date

    def initialize(site_num, json, storage, date, appointments)
      super(storage)
      @site_num = site_num
      @json = json
      @date = date
      @appointments = appointments
    end

    def name
      @json['name']
    end

    def title
      "#{name} on #{date}"
    end

    def address
      addr = @json['street_address_1']
      addr += " #{@json['street_address_2']}" unless @json['street_address_2'].empty?
      addr + ", #{@json['city']} #{@json['state']} #{@json['postal_code']}"
    end

    def vaccine
      @json['services'].join(', ')
    end

    def link
      "https://curative.com/sites/#{@site_num}"
    end

    def sign_up_page
      link
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Vaccine:* #{vaccine}\n*Available appointments:* #{render_slack_appointments}\n*Link:* #{link}",
        },
      }
    end
  end
end
