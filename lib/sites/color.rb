require 'date'
require 'json'
require 'open-uri'

module Color
  BASE_URL = 'https://home.color.com/api/v1'.freeze
  TOKEN_URL = "#{BASE_URL}/get_onsite_claim".freeze
  APPOINTMENT_URL = "#{BASE_URL}/vaccination_appointments/availability".freeze
  SITES = ['natickmall'].freeze

  def self.all_clinics(storage, logger)
    SITES.flat_map do |site_name|
      sleep(2)
      begin
        logger.info "[Color] Checking site #{site_name}"
        clinics = Page.new(site_name, storage, logger).clinics
        logger.info '[Color] No appointments found' if clinics.empty?
        clinics
      rescue => e
        Sentry.capture_exception(e)
        logger.error "[Color] Failed to get appointments for site #{site_name}: #{e}"
        []
      end
    end
  end

  class Page
    def initialize(site_name, storage, logger)
      @short_name = site_name
      token_response = JSON.parse(URI.parse("#{TOKEN_URL}?partner=#{site_name}").open.read)
      token = token_response['token']
      @site_info = token_response['population_settings']['collection_sites'][0]
      @json = JSON.parse(URI.parse("#{APPOINTMENT_URL}?claim_token=#{token}&collection_site=#{@site_info['name']}").open.read)
      @storage = storage
      @logger = logger
    end

    def appointments_by_date
      @logger.info(@json['results']) if @json['results'].any?
      @json['results'].each_with_object(Hash.new(0)) do |window, h|
        date = DateTime.parse(window['start'])
        h["#{date.month}/#{date.day}/#{date.year}"] += window['remaining_spaces']
      end
    end

    def clinics
      appointments_by_date.map do |date, appointments|
        @logger.info "[Color] Site #{@short_name} on #{date}: found #{appointments} appointments" if appointments.positive?
        Clinic.new(@short_name, @site_info, @storage, date, appointments)
      end
    end
  end

  class Clinic
    attr_reader :appointments, :date

    def initialize(short_name, site_info, storage, date, appointments)
      @short_name = short_name
      @site_info = site_info
      @storage = storage
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
      "https://home.color.com/vaccine/register/#{@short_name}"
    end

    def has_not_posted_recently?
      (Time.now - last_posted_time) > 600 # 10 minutes
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Available appointments:* #{render_appointments}\n*Link:* #{link}",
        },
      }
    end

    def sign_up_page
      link
    end

    def twitter_text
      "#{appointments} appointments available at #{title}. Check eligibility and sign up at #{sign_up_page}"
    end

    def last_posted_time
      DateTime.parse(@storage.get_post_time(self) || '2021-January-1').to_time
    end
  end
end
