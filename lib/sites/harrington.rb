require 'rest-client'
require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module Harrington
  SIGN_UP_URL = 'https://www.harringtonhospital.org/coronavirus/covid-19-vaccination/'.freeze
  API_URL = 'https://app.acuityscheduling.com/schedule.php?action=showCalendar&fulldate=1&owner=22192301&template=weekly'.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Harrington] Checking site'
    SentryHelper.catch_errors(logger, 'Harrington') do
      fetch_appointments.map do |date, appointments|
        logger.info "[Harrington] Found #{appointments} appointments on #{date}"
        Clinic.new(storage, date, appointments)
      end
    end
  end

  def self.fetch_appointments
    res = RestClient.post(
      API_URL, {
        type: 20819310,
        calendar: 5202038,
        skip: true,
        'options[qty]' => 1,
        'options[numDays]' => 27,
        ignoreAppointment: '',
        appointmentType: '',
        calendarID: 5202038,
      }
    )
    html = Nokogiri::HTML(res.body)
    html.search('input.time-selection').each_with_object(Hash.new(0)) do |appt, h|
      h[appt['data-readable-date']] += 1
    end
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments

    def initialize(storage, date, appointments)
      super(storage)
      @date = date
      @appointments = appointments
    end

    def name
      'Southbridge Community Center in Southbridge MA'
    end

    def title
      "#{name} on #{date}"
    end

    def link
      SIGN_UP_URL
    end
  end
end
