require 'date'
require 'nokogiri'
require 'open-uri'
require 'rest-client'
require 'sentry-ruby'

module MaImmunizations
  BASE_URL = "https://www.maimmunizations.org/clinic/search?q[services_name_in][]=Vaccination".freeze

  def self.all_clinics(storage, logger, cookie_helper)
    unconsolidated_clinics(storage, logger, cookie_helper).each_with_object({}) do |clinic, h|
      if h[clinic.title]
        h[clinic.title].appointments += clinic.appointments
      else
        h[clinic.title] = clinic
      end
    end.values
  end

  def self.unconsolidated_clinics(storage, logger, cookie_helper)
    page_num = 1
    clinics = []
    loop do
      begin
        raise "Too many pages: #{page_num}" if page_num > 100

        logger.info "[MaImmunizations] Checking page #{page_num}"
        page = Page.new(page_num, storage, logger, cookie_helper)
        clinics += page.clinics
        return clinics if page.final_page?
      rescue => e
        Sentry.capture_exception(e)
        logger.error "[MaImmunizations] Failed to get appointments on page #{page_num}: #{e}"
        return clinics
      end

      page_num += 1
      sleep(2)
    end
  end

  class WaitingPageHelper
    COOKIE_SITE = 'ma-immunization'.freeze

    def initialize(logger, storage)
      @logger = logger
      @storage = storage
      init_cookies
    end

    def init_cookies
      existing_cookies = @storage.get_cookies(COOKIE_SITE)
      if existing_cookies
        @logger.info '[MaImmunizations] Got existing cookies from storage'
        @cookies = existing_cookies['cookies']
        @cookie_expiration = Time.parse(existing_cookies['expiration'])
      end
      refresh_cookies
    end

    def refresh_cookies(force: false)
      if !force && @cookies && @cookie_expiration && @cookie_expiration > (Time.now + 60 * 60)
        @logger.info '[MaImmunizations] Skipping setting cookies'
      else
        @logger.info '[MaImmunizations] Setting cookies'
        response = RestClient.get(BASE_URL)
        @cookies = response.cookies
        @cookie_expiration = response.cookie_jar.map(&:expires_at).min
        @storage.save_cookies(COOKIE_SITE, @cookies, @cookie_expiration)
      end

      @logger.info '[MaImmunizations] Starting waiting page'
      iter = 0
      loop do
        sleep(5)
        response = RestClient.get(BASE_URL, cookies: @cookies).body
        break if /Find a Vaccination Clinic/ =~ response

        if iter == 12 # wait a minute before checking other sites
          minutes_left = /estimated wait time is\s*([\d\w\s]+)\./.match(response.gsub('\n', ''))
          if minutes_left
            @logger.info "[MaImmunizations] Waited too long, estimate left: #{minutes_left[1]}"
          else
            @logger.info '[MaImmunizations] Waited too long, no estimate found'
          end
          return
        end

        iter += 1
      end
      @logger.info '[MaImmunizations] Made it through waiting page'
    end

    def cookies
      refresh_cookies unless @cookies && @cookie_expiration

      # Try to refresh cookies around midnight if they're going to expire today
      now = Time.now
      refresh_cookies(force: true) if @cookie_expiration.year == now.year &&
                                      @cookie_expiration.month == now.month &&
                                      @cookie_expiration.day == now.day

      @cookies
    end
  end

  class Page
    def initialize(page, storage, logger, cookie_helper)
      response = RestClient.get(BASE_URL + "&page=#{page}", cookies: cookie_helper.cookies).body
      if /Find a Vaccination Clinic/ !~ response
        logger.info '[MaImmunizations] Got waiting page'
        cookie_helper.refresh_cookies
        response = RestClient.get(BASE_URL + "&page=#{page}", cookies: cookie_helper.cookies).body
      end

      @doc = Nokogiri::HTML(response)
      @storage = storage
      @logger = logger
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

  class Clinic
    TITLE_MATCHER = %r[^(.+) on (\d{2}/\d{2}/\d{4})$].freeze

    attr_accessor :appointments

    def initialize(group, storage)
      @group = group
      @storage = storage
      @paragraphs = group.search('p')
      @appointments = parse_appointments
    end

    def valid?
      @paragraphs.any? && !@paragraphs[7].nil?
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

    def vaccine
      match = /Vaccinations offered:\s+(.+)$/.match(@paragraphs[2].content)
      match && match[1]
    end

    def age_groups
      match = /Age groups served:\s+(.+)$/.match(@paragraphs[3].content)
      match && match[1]
    end

    def additional_info
      match = /Additional Information:\s+(.+)$/.match(@paragraphs[5].content)
      match && match[1]
    end

    def parse_appointments
      return 0 unless @paragraphs && @paragraphs[7]

      match = /Available Appointments\s+: (\d+)/.match(@paragraphs[7].content)
      return 0 unless match

      match[1].to_i
    end

    def link
      return nil unless @paragraphs[8]

      'https://www.maimmunizations.org' + @paragraphs[8].search('a')[0]['href']
    end

    def has_not_posted_recently?
      (Time.now - last_posted_time) > 600 # 10 minutes
    end

    def name
      match = TITLE_MATCHER.match(title)
      match && match[1]
    end

    def date
      match = TITLE_MATCHER.match(title)
      match && DateTime.parse(match[2])
    end

    def render_appointments
      appointment_txt = "#{appointments} (#{new_appointments} new)"
      if appointments >= 10
        ":siren: #{appointment_txt} :siren:"
      else
        appointment_txt
      end
    end

    def new_appointments
      appointments - last_appointments
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Vaccine:* #{vaccine}\n*Age groups*: #{age_groups}\n*Available appointments:* #{render_appointments}\n*Additional info:* #{additional_info}\n*Link:* #{link}",
        },
      }
    end

    def sign_up_page
      addr = 'https://www.maimmunizations.org/clinic/search?'
      addr += "q[venue_search_name_or_venue_name_i_cont]=#{name}&" if name
      URI.parse(addr)
    end

    def twitter_text
      "#{appointments} appointments available at #{title}. Check eligibility and sign up at #{sign_up_page}"
    end

    def storage_key
      title
    end

    def save_appointments
      @storage.save_appointments(self)
    end

    def last_appointments
      @storage.get_appointments(self)&.to_i || 0
    end

    def save_tweet_time
      @storage.save_post_time(self)
    end

    def last_posted_time
      DateTime.parse(@storage.get_post_time(self) || '2021-January-1').to_time
    end
  end
end
