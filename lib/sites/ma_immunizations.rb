require 'date'
require 'nokogiri'
require 'open-uri'
require 'rest-client'
require 'sentry-ruby'

require_relative '../sentry_helper'
require_relative './base_clinic'

module MaImmunizations
  BASE_URL = "https://clinics.maimmunizations.org/clinic/search?q[services_name_in][]=Vaccination".freeze

  def self.all_clinics(storage, logger)
    unconsolidated_clinics(storage, logger).each_with_object({}) do |clinic, h|
      if h[clinic.title]
        h[clinic.title].appointments += clinic.appointments
      else
        h[clinic.title] = clinic
      end
    end.values
  end

  def self.unconsolidated_clinics(storage, logger)
    page_num = 1
    clinics = []
    SentryHelper.catch_errors(logger, 'MaImmunizations', on_error: clinics) do
      loop do
        raise "Too many pages: #{page_num}" if page_num > 100

        logger.info "[MaImmunizations] Checking page #{page_num}"
        page = Page.new(page_num, storage, logger)
        page.fetch
        return clinics if page.waiting_page

        clinics += page.clinics
        return clinics if page.final_page?

        page_num += 1
        sleep(2)
      end
    end
    clinics
  end

  class Page
    CLINIC_PAGE_IDENTIFIER = /Find a Vaccination Clinic/.freeze
    COOKIE_SITE = 'ma-immunization'.freeze

    attr_reader :waiting_page

    def initialize(page, storage, logger)
      @page = page
      @storage = storage
      @logger = logger
      @waiting_page = true
    end

    def fetch
      cookies = get_cookies
      response = RestClient.get(BASE_URL + "&page=#{@page}", cookies: cookies).body

      if CLINIC_PAGE_IDENTIFIER !~ response
        @logger.info '[MaImmunizations] Got waiting page'
        12.times do
          response = RestClient.get(BASE_URL + "&page=#{@page}", cookies: cookies).body
          break if CLINIC_PAGE_IDENTIFIER =~ response

          sleep(5)
        end
      end

      if CLINIC_PAGE_IDENTIFIER =~ response
        @logger.info '[MaImmunizations] Made it through waiting page'
        @waiting_page = false
      else
        minutes_left = /(\d+) minute/.match(response)
        if minutes_left
          @logger.info "[MaImmunizations] Waited too long, estimate left: #{minutes_left[1]}"
        else
          @logger.info '[MaImmunizations] Waited too long, no estimate found'
        end
      end

      @doc = Nokogiri::HTML(response)
    end

    def get_cookies
      existing_cookies = @storage.get_cookies(COOKIE_SITE) || {}
      cookies = existing_cookies['cookies']
      if cookies
        cookie_expiration = Time.parse(existing_cookies['expiration'])
        # use existing cookies unless they're expired
        if cookie_expiration > Time.now
          @logger.info '[MaImmunizations] Using existing cookies'
          return cookies
        end
      end

      @logger.info '[MaImmunizations] Getting new cookies'
      response = RestClient.get(BASE_URL, cookies: cookies)
      new_cookies = response.cookies
      cookie_expiration = response.cookie_jar.map(&:expires_at).compact.min
      @storage.save_cookies(COOKIE_SITE, new_cookies, cookie_expiration)
      new_cookies
    end

    def final_page?
      @doc.search('.page.next').empty? || @doc.search('.page.next.disabled').any?
    end

    def clinics
      container = @doc.search('.main-container > div')[1]

      unless container
        @logger.warn "[MaImmunizations] Couldn't find main page container!"
        return []
      end

      results = container.search('> div.justify-between').map do |group|
        Clinic.new(group, @storage)
      end.filter do |clinic|
        clinic.valid?
      end

      unless results.any?
        Sentry.capture_message("[MaImmunizations] Couldn't find any clinics!")
        @logger.warn "[MaImmunizations] Couldn't find any clinics!"
      end

      results.filter do |clinic|
        clinic.appointments.positive?
      end.each do |clinic|
        @logger.info "[MaImmunizations] Site #{clinic.title}: found #{clinic.appointments} appointments (link: #{!clinic.link.nil?})"
      end

      results
    end
  end

  class Clinic < BaseClinic
    TITLE_MATCHER = %r[^(.+) on (\d{2}/\d{2}/\d{4})$].freeze

    attr_accessor :appointments

    def initialize(group, storage)
      super(storage)
      @group = group
      @paragraphs = group.search('p')
      @parsed_info = @paragraphs[2..].each_with_object({}) do |p, h|
        match = /^([\w\d\s]+):\s+(.+)$/.match(p.content)
        next unless match

        h[match[1].strip] = match[2].strip
      end
      @appointments = @parsed_info['Available Appointments'].to_i
    end

    def valid?
      @parsed_info.key?('Available Appointments')
    end

    def to_s
      "Clinic: #{title}"
    end

    def title
      @paragraphs[0].content.strip
    end

    def address
      @paragraphs[1].content.strip
    end

    def city
      match = address.match(/^.*, ([\w\d\s]+) (MA|Massachusetts),/i)
      return nil unless match

      match[1]
    end

    def vaccine
      @parsed_info['Vaccinations offered']
    end

    def age_groups
      @parsed_info['Age groups served']
    end

    def additional_info
      @parsed_info['Additional Information']
    end

    def link
      a_tag = @paragraphs.last.search('a')
      return nil unless a_tag.any?

      'https://www.maimmunizations.org' + a_tag[0]['href']
    end

    def name
      match = TITLE_MATCHER.match(title)
      match[1].strip
    end

    def date
      match = TITLE_MATCHER.match(title)
      match[2]
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Vaccine:* #{vaccine}\n*Age groups*: #{age_groups}\n*Available appointments:* #{render_slack_appointments}\n*Additional info:* #{additional_info}\n*Link:* #{link}",
        },
      }
    end

    def twitter_text
      txt = "#{appointments} appointments available at #{name}"
      txt += " in #{city}, MA" if city
      txt + " on #{date}. Check eligibility and sign up at #{sign_up_page}"
    end

    def sign_up_page
      addr = 'https://www.maimmunizations.org/clinic/search?'
      addr += "q[venue_search_name_or_venue_name_i_cont]=#{name}&" if name
      URI.parse(addr)
    end
  end
end
