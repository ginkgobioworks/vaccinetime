require 'date'
require 'json'
require 'rest-client'

require_relative '../sentry_helper'

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
      return [] if appointments_are_hidden?

      appointments_by_date.map do |k, v|
        @logger.info "[Curative] Site #{@site_num} on #{k}: found #{v} appoinments" if v.positive?
        Clinic.new(@site_num, @json, @storage, k, v)
      end
    end

    def appointments_are_hidden?
      if !Date.today.thursday? && ENV['ENVIRONMENT'] == 'production'
        @logger.info "[Curative] Site #{@site_num} appointments are hidden on days besides Thursday in prod"
        return true
      end

      base_site = RestClient.get(BASE_URL + @site_num.to_s)
      sign_up_key = "#{SIGN_UP_SEEN_KEY}:#{@site_num}"

      if base_site.code != 200
        @logger.info "[Curative] Site #{@site_num} not available, returned code #{base_site.code}"
        return true
      end

      if base_site.request.url.start_with?("#{QUEUE_SITE}/afterevent")
        @logger.info "[Curative] Site #{@site_num} event has ended"
        return true
      end

      if base_site.request.url.start_with?(QUEUE_SITE) &&
          /MA COVID-19 vaccination appointment sign-ups have not yet begun/ =~ base_site.body
        @logger.info "[Curative] Site #{@site_num} is waiting for the sign up event"
        @storage.set(sign_up_key, Time.now)
        return true
      end

      sign_up_last_seen = @storage.get(sign_up_key)
      if sign_up_last_seen && Date.parse(sign_up_last_seen) == Date.today
        @logger.info "[Curative] Site #{@site_num} is open after the sign up message today"
        return false
      end

      @logger.info "[Curative] Site #{@site_num} is hidden because there was no queue seen today"
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

  class Clinic
    attr_reader :appointments, :date

    def initialize(site_num, json, storage, date, appointments)
      @site_num = site_num
      @json = json
      @storage = storage
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

    def storage_key
      title
    end

    def save_appointments
      @storage.save_appointments(self)
    end

    def save_tweet_time
      @storage.save_post_time(self)
    end

    def last_appointments
      @storage.get_appointments(self)&.to_i || 0
    end

    def new_appointments
      appointments - last_appointments
    end

    def render_appointments
      appointment_txt = "#{appointments} (#{new_appointments} new)"
      if appointments >= 10
        ":siren: #{appointment_txt} :siren:"
      else
        appointment_txt
      end
    end

    def link
      "https://curative.com/sites/#{@site_num}"
    end

    def has_not_posted_recently?
      (Time.now - last_posted_time) > 600 # 10 minutes
    end

    def sign_up_page
      link
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Vaccine:* #{vaccine}\n*Available appointments:* #{render_appointments}\n*Link:* #{link}",
        },
      }
    end

    def twitter_text
      "#{appointments} appointments available at #{title}. Check eligibility and sign up at #{sign_up_page}"
    end

    def last_posted_time
      DateTime.parse(@storage.get_post_time(self) || '2021-January-1').to_time
    end
  end
end
