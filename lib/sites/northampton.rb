require 'rest-client'
require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Northampton
  BASE_URL = 'https://www.northamptonma.gov/2219/Vaccine-Clinics'.freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Northampton') do
      res = RestClient.get(BASE_URL).body
      sites = res.scan(%r{https://www\.(maimmunizations\.org//reg/\d+)})
      logger.info '[Northampton] No sites found' if sites.empty?
      sites.each_with_object(Hash.new(0)) do |clinic_url, h|
        sleep(1)
        reg_url = "https://registrations.#{clinic_url[0]}"
        scrape_result = scrape_registration_site(storage, logger, reg_url)
        next unless scrape_result

        h[scrape_result[0]] += scrape_result[1]
      end.map do |title, appointments|
        Clinic.new(storage, title, BASE_URL, appointments)
      end
    end
  end

  def self.scrape_registration_site(storage, logger, url)
    logger.info "[Northampton] Checking site #{url}"
    res = RestClient.get(url).body

    if /Clinic does not have any appointment slots available/ =~ res
      logger.info '[Northampton] No appointment slots available'
      return nil
    end

    if /This clinic is closed/ =~ res
      logger.info '[Northampton] Clinic is closed'
      return nil
    end

    clinic = Nokogiri::HTML(res)
    title_search = clinic.search('h1')
    unless title_search.any?
      logger.warn '[Northampton] No title found'
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

    logger.info "[Northampton] Found #{appointments} at #{title}" if appointments.positive?
    [title, appointments]
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
      match = TITLE_MATCHER.match(title)
      match[1].strip
    end

    def date
      match = TITLE_MATCHER.match(title)
      match[2]
    end

    def city
      'Northampton'
    end

    def twitter_text
      "#{appointments} appointments available at #{name} in #{city}, MA on #{date}. Check eligibility and sign up at #{sign_up_page}"
    end
  end
end
