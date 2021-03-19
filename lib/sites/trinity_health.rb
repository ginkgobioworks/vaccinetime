require 'date'
require 'rest-client'
require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module TrinityHealth
  BASE_URL = 'https://apps.sphp.com/THofNECOVIDVaccinations'.freeze

  def self.all_clinics(storage, logger)
    logger.info '[TrinityHealth] Checking site'
    date = Date.today - 1
    clinics = []

    SentryHelper.catch_errors(logger, 'TrinityHealth') do
      8.times do
        date += 1
        sleep(0.5)

        res = fetch_day(date)
        next if /There are no open appointments on this day. Please try another day./ =~ res

        returned_day = Nokogiri::HTML(res).search('#CurrentDay')[0]['data-date']

        appointments = res.scan(/Reserve Appointment/).size
        if appointments.positive?
          logger.info "[TrinityHealth] Found #{appointments} appointments on #{returned_day}"
          clinics << Clinic.new(storage, returned_day, appointments)
        end
      end
    end

    clinics
  end

  def self.fetch_day(date)
    day = date.strftime('%m/%d/%Y')
    RestClient.post(
      "#{BASE_URL}/livesearch.php",
      { ScheduleDay: day },
      cookies: { SiteName: 'THOfNE Mercy Medical Center' }
    ).body
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments

    NAME = 'Mercy Medical Center, Springfield MA'.freeze

    def initialize(storage, date, appointments)
      super(storage)
      @date = date
      @appointments = appointments
    end

    def title
      "#{NAME} on #{date}"
    end

    def link
      BASE_URL
    end

    def address
      '299 Carew Street, Springfield, MA 01104'
    end

    def slack_blocks
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*#{title}*\n*Address:* #{address}\n*Available appointments:* #{render_slack_appointments}\n*Link:* #{link}",
        },
      }
    end
  end
end
