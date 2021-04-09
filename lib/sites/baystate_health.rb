require 'json'
require 'rest-client'
require 'ferrum'

require_relative '../sentry_helper'
require_relative './base_clinic'

module BaystateHealth
  SIGN_UP_URL = 'https://workwell.apps.baystatehealth.org/guest/covid-vaccine/register?r=mafirstresp210121'.freeze
  API_URL = 'https://mobileprod.api.baystatehealth.org/workwell/schedules/campaigns?camId=mafirstresp210121&activeOnly=1&includeVac=1&includeSeat=1'.freeze

  # Baystate Health doesn't provide appointment info without registering, but
  # we can get the total number of vaccines available and put them all in one
  # clinic without a date
  def self.all_clinics(storage, logger)
    logger.info '[BaystateHealth] Checking site'

    clinic = Clinic.new(storage)

    SentryHelper.catch_errors(logger, 'BaystateHealth') do
      return [] unless registration_available?(logger)

      JSON.parse(RestClient.get(API_URL).body)['campaigns'].each do |campaign|
        next unless campaign['active'] == 1

        campaign['vaccines'].each do |vaccine|
          next unless vaccine['status'] == 'ACTIVE' && vaccine['cvaActive'] == 1 && vaccine['dose1Available'].positive?

          locations = vaccine['locations'].map { |l| l['city'] }.reject(&:empty?)
          next unless locations.any?

          logger.info("[BaystateHealth] Found #{vaccine['dose1Available']} appointments for #{vaccine['name']}")
          clinic.appointments += vaccine['dose1Available']
          clinic.locations.merge(locations)
          clinic.vaccines.add(vaccine['name'])
        end
      end
    end

    [clinic]
  end

  def self.registration_available?(logger)
    browser = if ENV['IN_DOCKER'] == 'true'
                Ferrum::Browser.new(browser_options: { 'no-sandbox': nil })
              else
                Ferrum::Browser.new
              end

    browser.goto(SIGN_UP_URL)

    5.times do
      browser.network.wait_for_idle
      html = Nokogiri.parse(browser.body)

      h3 = html.search('.content-card h3')
      if h3.any?
        browser.quit
        if h3[0].text.include?('Registration Temporarily Unavailable')
          logger.info '[BaystateHealth] Registration unavailable'
          return false
        else
          return true
        end
      else
        sleep 1
      end
    end

    logger.info "[BaystateHealth] Didn't load"
    browser.quit

    false
  end

  class Clinic < BaseClinic
    attr_accessor :appointments, :locations, :vaccines

    def initialize(storage)
      super(storage)
      @appointments = 0
      @locations = Set.new
      @vaccines = Set.new
    end

    def title
      'Baystate Health'
    end

    def link
      SIGN_UP_URL
    end

    def sign_up_page
      link
    end

    def twitter_text
      txt = "#{appointments} appointments available at #{title} (in #{locations.join('/')})"
      txt += " for #{vaccines.join(', ')}" if vaccines.any?
      txt + ". Check eligibility and sign up at #{sign_up_page}"
    end
  end
end
