require 'rest-client'
require 'nokogiri'

require_relative './base_clinic'

module MaImmunizationsRegistrations
  def self.all_clinics(sign_up_page, pages, storage, logger, additional_info = nil)
    pages.each_with_object(Hash.new(0)) do |clinic_url, h|
      sleep(1)
      scrape_result = scrape_registration_site(logger, clinic_url)
      next unless scrape_result

      h[[scrape_result[0], scrape_result[1]]] += scrape_result[2]
    end.map do |(title, vaccine), appointments|
      Clinic.new(storage, title, sign_up_page, appointments, vaccine, additional_info)
    end
  end

  def self.scrape_registration_site(logger, url)
    logger.info "[MaImmunizationsRegistrations] Checking site #{url}"
    res = RestClient.get(url).body

    if /Clinic does not have any appointment slots available/ =~ res
      logger.info '[MaImmunizationsRegistrations] No appointment slots available'
      return nil
    end

    if /This clinic is closed/ =~ res
      logger.info '[MaImmunizationsRegistrations] Clinic is closed'
      return nil
    end

    clinic = Nokogiri::HTML(res)
    title_search = clinic.search('h1')
    unless title_search.any?
      logger.warn '[MaImmunizationsRegistrations] No title found'
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

    vaccine = nil
    button = clinic.search('#submitButton')[0]
    if button['data-pfizer-clinic'] == 'true'
      vaccine = 'Pfizer-BioNTech COVID-19 Vaccine'
    elsif button['data-moderna-clinic'] == 'true'
      vaccine = 'Moderna COVID-19 Vaccine'
    elsif button['data-janssen-clinic'] == 'true'
      vaccine = 'Janssen COVID-19 Vaccine'
    end

    logger.info "[MaImmunizationsRegistrations] Found #{appointments} at #{title}" if appointments.positive?
    [title, vaccine, appointments]
  end

  class Clinic < BaseClinic
    TITLE_MATCHER = %r[^(.+) on (\d{2}/\d{2}/\d{4})$].freeze
    TWEET_INCREASE_NEEDED = 50
    TWEET_COOLDOWN = 3600 # 1 hour

    attr_reader :title, :link, :appointments, :vaccine

    def initialize(storage, title, link, appointments, vaccine, additional_info)
      super(storage)
      @title = title
      @link = link
      @appointments = appointments
      @vaccine = vaccine
      @additional_info = additional_info
    end

    def name
      match = TITLE_MATCHER.match(title)
      match[1].strip
    end

    def date
      match = TITLE_MATCHER.match(title)
      match[2]
    end

    def twitter_text
      txt = "#{appointments} appointments available at #{title}"
      txt += " for #{vaccine}" if vaccine
      txt += " (#{@additional_info})" if @additional_info
      txt + ". Check eligibility and sign up at #{sign_up_page}"
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Vaccine:* #{vaccine}\n*Available appointments:* #{render_slack_appointments}\n*Additional info:* #{@additional_info}\n*Link:* #{link}",
        },
      }
    end
  end
end
