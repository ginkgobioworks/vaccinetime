require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Rutland
  BASE_URL = 'https://www.rrecc.us/k12'.freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Rutland') do
      res = RestClient.get(BASE_URL).body
      sites = res.scan(%r{www\.maimmunizations\.org__reg_(\d+)&})
      logger.info '[Rutland] No sites found' if sites.empty?
      sites.map do |clinic_num|
        sleep(2)
        reg_url = "https://registrations.maimmunizations.org//reg/#{clinic_num[0]}"
        scrape_registration_site(storage, logger, reg_url)
      end.compact
    end
  end

  def self.scrape_registration_site(storage, logger, url)
    logger.info "[Rutland] Checking site #{url}"
    res = RestClient.get(url).body

    if /Clinic does not have any appointment slots available/ =~ res
      logger.info '[Rutland] No appointment slots available'
      return nil
    end

    if /This clinic is closed/ =~ res
      logger.info '[Rutland] Clinic is closed'
      return nil
    end

    clinic = Nokogiri::HTML(res)
    title_search = clinic.search('h1')
    unless title_search.any?
      logger.warn '[Rutland] No title found'
      return nil
    end

    title = /Sign Up for Vaccinations - (.+)$/.match(title_search[0].text)[1].strip
    appointments = clinic.search('tbody tr').reduce(0) do |val, row|
      entry = row.search('td').last.text.split.join(' ')
      match = /(\d+) appointments available/.match(entry)
      if match
        val + match[1].to_i
      else
        val
      end
    end

    logger.info "[Rutland] Found #{appointments} at #{title}" if appointments.positive?
    Clinic.new(storage, title, BASE_URL, appointments)
  end

  class Clinic < BaseClinic
    TITLE_MATCHER = %r[^(.+) on (\d{2}/\d{2}/\d{4})$].freeze

    attr_reader :title, :link, :appointments

    def initialize(storage, title, link, appointments)
      super(storage)
      @title = title
      @link = link
      @appointments = appointments
    end

    def name
      puts title
      match = TITLE_MATCHER.match(title)
      match[1].strip
    end

    def date
      match = TITLE_MATCHER.match(title)
      match[2]
    end

    def twitter_text
      "#{appointments} appointments available at #{name} (teachers only) on #{date}. Check eligibility and sign up at #{sign_up_page}"
    end
  end
end
