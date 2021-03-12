require 'date'
require 'json'
require 'nokogiri'
require 'rest-client'
require 'sentry-ruby'

require_relative '../sentry_helper'
require_relative './base_clinic'

module LowellGeneral
  BASE_URL = 'https://www.lowellgeneralvaccine.com/schedule.html'.freeze
  DOCTOR_URL = 'https://lowell-general-hospital---covid---19-vaccination.healthpost.com'.freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'LowellGeneral') do
      all_stations(logger).each_with_object(Hash.new({ stations: [], appointments: 0 })) do |station, h|
        station.appointments_by_date.each do |date, num|
          h[date][:appointments] += num
          h[date][:stations] << station.num if num.positive?
        end
      end.map do |date, station_data|
        Clinic.new(storage, station_data[:stations], station_data[:appointments], date)
      end
    end
  end

  def self.all_stations(logger)
    logger.info '[LowellGeneral] Looking up eligible stations'

    response = RestClient::Request.execute(method: :get, url: BASE_URL, verify_ssl: false)
    stations = response.body.scan(%r[https://lowell-general-hospital---covid---19-vaccination\.healthpost\.com/embed\.js\?doctor_id=(\d+-covid-19-vaccination-station-(\d+))&])

    if stations.empty?
      logger.info '[LowellGeneral] No stations found'
      return []
    end

    logger.info "[LowellGeneral] Found stations #{stations.map(&:last).join(', ')}"
    stations.map do |doctor_url, num|
      Station.new(logger, num, doctor_url)
    end
  end

  class Station
    STATION_URL = 'https://lowell-general-hospital---covid---19-vaccination.healthpost.com'.freeze

    attr_reader :num

    def initialize(logger, num, doctor_url)
      @logger = logger
      @num = num
      @doctor_url = doctor_url
    end

    def appointments_by_date
      body = appointments_nokogiri
      return {} unless body

      headers = body.search('table tr')[0].search('th')
      cols = body.search('table tr')[1].search('td')
      return {} if cols.length == 1 || headers.length != cols.length

      headers.zip(cols).map do |header, slots|
        [header.text.split(' ').join(' '), slots.search('li a').length]
      end.to_h
    rescue => e
      Sentry.capture_exception(e)
      @logger.error "[LowellGeneral] Station #{@num} failed to fetch: #{e}"
      {}
    end

    def appointments_nokogiri
      appts = fetch_appointments(appointments_url)
      return nil unless appts

      next_appt_link = appts.search('.next-available-appt a')
      if next_appt_link.any?
        @logger.info "[LowellGeneral] Station #{@num} found appointments at a future date"
        fetch_appointments(next_appt_link[0]['href'])
      else
        appts
      end
    end

    def fetch_appointments(url)
      @logger.info "[LowellGeneral] Station #{@num} fetching data"
      res = RestClient.get(url)
      match = /server_response_for_update\((.*)\);$/.match(res)
      return nil unless match

      body = JSON.parse(match[1])
      div = Nokogiri::HTML(body['time_slots_div'])
      return nil if div.search('.no_availability').any?

      div
    end

    def appointments_url
      now = Time.now
      days_away = 7
      future = Time.now + (days_away * 24 * 60 * 60)
      "#{STATION_URL}/doctors/#{@doctor_url}/time_slots" \
        '?appointment_action=new' \
        '&embed=1' \
        "&end_at=#{date_for_url(future)}" \
        '&hp_medium=widget_provider' \
        '&hp_source=lowell-general-hospital---covid---19-vaccination' \
        '&html_container_id=healthpost_appointments22' \
        '&practice_location_id=14110' \
        "&start_at=#{date_for_url(now)}" \
        "&num_of_days=#{days_away}"
    end

    def date_for_url(date)
      date.strftime('%Y-%m-%d %H:%M:%S')
    end
  end

  class Clinic < BaseClinic
    attr_reader :appointments

    def initialize(storage, stations, appointments, date)
      super(storage)
      @stations = stations
      @appointments = appointments
      @date = DateTime.parse(date).strftime('%m/%d/%Y')
    end

    def title
      "Lowell General Hospital on #{date}"
    end

    def link
      'https://www.lowellgeneralvaccine.com/'
    end

    def sign_up_page
      link
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Available appointments:* #{render_slack_appointments}\n*Stations:* #{@stations.join(', ')}\n*Link:* #{link}",
        },
      }
    end
  end
end
