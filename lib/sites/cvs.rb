require 'date'
require 'json'
require 'rest-client'

require_relative './base_clinic'

module Cvs
  STATE = 'MA'
  USER_AGENTS = []
  CVS_CITIES = {}

  class CvsCity
    attr_reader :city, :stores, :should_tweet

    def initialize(city, stores, should_tweet)
      @city = city
      @stores = stores
      @should_tweet = should_tweet
    end
  end

  File.open("user_agents.txt", "r") do |f|
    f.each_line do |line|
      USER_AGENTS.append(line.strip)
    end
  end

  File.open("cvs_locations.csv", "r") do |f|
    lines = f.lines
    lines.next # skip header
    lines.each do |line|
      entry = line.strip.split(',')
      city = entry[0]
      stores = entry[1].to_i
      should_tweet = entry[2] == "1"
      CVS_CITIES[city] = CvsCity.new(city, stores, should_tweet)
    end
  end

  # This array also defines the order in which city names appear, the order is determined
  # by the number of stores in a city.
  TWEET_ALLOWED_CITIES = CVS_CITIES.keys.filter { |cvs_city| CVS_CITIES[cvs_city].should_tweet }
                                   .sort_by { |cvs_city| -1 * CVS_CITIES[cvs_city].stores }

  def self.state_clinic_representation(storage, logger)
    clinics = []
    SentryHelper.catch_errors(logger, 'MaImmunizations', on_error: clinics) do
      # For now, CVS is counted as one "clinic" for the whole state and every city offering
      # with stores offering the vaccine is counted as one "appointment".
      cvs_client = CvsClient.new(STATE, USER_AGENTS)
      cvs_client.init_session(logger)

      cities_with_appointments = cvs_client.cities_with_appointments(logger)
      if cities_with_appointments.any?
        logger.info "[CVS] There are #{cities_with_appointments.length} cities with appointments"
        logger.info "[CVS] Cities with appointments: #{cities_with_appointments.join(", ")}"
      else
        logger.info "[CVS] No availability for any city in #{STATE}"
      end

      clinics = [StateClinic.new(storage, cities_with_appointments, STATE)]
    end

    return clinics
  end

  class StateClinic < BaseClinic
    LAST_SEEN_CITIES_KEY = "cvs-last-cities".freeze

    attr_accessor :appointments

    def initialize(storage, cities, state)
      super(storage)
      @cities = cities.sort_by { |city| -1 * (CVS_CITIES[city].nil? ? 1 : CVS_CITIES[city].stores) }
      @state = state
      @appointments = @cities.length
    end

    def title
      "CVS stores in #{@state}"
    end

    def appointments
      @cities.length
    end

    def last_appointments
      last_cities.length
    end

    def new_appointments
      new_cities.length
    end

    def link
      "https://www.cvs.com/immunizations/covid-19-vaccine"
    end

    def sign_up_page
      link
    end

    def twitter_text
      new_cities = tweet_allowed_new_cities
      cities_text = new_cities.shift
      while (city = new_cities.shift) do
        pending_text = ", #{city}"
        if cities_text.length + pending_text.length > 176
          cities_text += ", and #{new_cities.length + 1} others"
          break
        else
          cities_text += pending_text
        end
      end

      #  30 chars: "CVS appointments available in "
      # 176 chars: max of cities_text
      #  16 chars: ", and NNN others"
      #  35 chars: ". Check eligibility and sign up at "
      #  23 chars: shortened link
      # ---------
      # 280 chars total, 280 is the maximum
      "CVS appointments available in #{cities_text}. Check eligibility and sign up at #{sign_up_page}"
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Available appointments in #{@cities.join(', ')}*\n*Link:* #{link}",
        },
      }
    end

    def save_appointments
      @storage.set(LAST_SEEN_CITIES_KEY + ':' + @state, @cities.join(','))
    end

    def last_cities
      stored_value = @storage.get(LAST_SEEN_CITIES_KEY + ':' + @state)
      stored_value.nil? ? [] : stored_value.split(',')
    end

    def new_cities
      @cities - last_cities
    end

    def tweet_allowed_new_cities
      new_cities.filter { |new_city| TWEET_ALLOWED_CITIES.include? new_city }
    end

    def should_tweet?
      tweet_allowed_new_cities.length > 5 && has_not_posted_recently?
    end
  end

  class CvsClient

    def initialize(state, user_agents)
      @cookies = {}
      @user_agents = user_agents
      @user_agent = @user_agents.sample
      @state = state
      @state_status_url = "https://www.cvs.com/immunizations/covid-19-vaccine.vaccine-status.#{state}.json?vaccineinfo".freeze
    end

    def init_session(logger)
      @user_agent = @user_agents.sample
      headers = {
        :Referer => 'https://www.cvs.com/',
        :accept => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
        :user_agent => @user_agent,
      }
      begin
        response = RestClient.get('https://www.cvs.com', headers)
        @cookies = response.cookies
      rescue RestClient::Exception => e
        logger.warn "[CVS] Failed to get cookies: #{e} - #{e.response}"
      end
    end

    def cities_with_appointments(logger)
      logger.info "[CVS] Checking status for all cities in #{@state}"
      headers = {
        :Referer => "https://www.cvs.com/immunizations/covid-19-vaccine?icid=cvs-home-hero1-banner-1-link2-coronavirus-vaccine",
        :user_agent => @user_agent,
        :cookies => @cookies
      }
      begin
        response = JSON.parse(RestClient.get(@state_status_url, headers))
      rescue RestClient::Exception => e
        logger.error "[CVS] Failed to get state status for #{@state}: #{e}"
        return []
      end
      if response['responsePayloadData'].nil? || response['responsePayloadData']['data'].nil? ||
        response['responsePayloadData']['data'][@state].nil?
        logger.warn "[CVS] Response for state status missing 'responsePayloadData.data.#{@state}' field: #{response}"
        return []
      end
      response['responsePayloadData']['data'][@state].filter do |location|
        location['status'] == 'Available'
      end.map do | location |
        location['city']
      end
    end
  end
end
