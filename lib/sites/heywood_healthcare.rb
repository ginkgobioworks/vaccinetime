require 'rest-client'
require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module HeywoodHealthcare
  SIGN_UP_URL = 'https://gardnervaccinations.as.me/schedule.php'.freeze
  API_URL = 'https://gardnervaccinations.as.me/schedule.php?action=showCalendar&fulldate=1&owner=21588707&template=class'.freeze
  SITE_NAME = 'Heywood Healthcare in Gardner, MA'.freeze

  def self.all_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'HeywoodHealthcare') do
      logger.info '[HeywoodHealthcare] Checking site'
      unless appointments?
        logger.info '[HeywoodHealthcare] No appointments available'
        return []
      end

      fetch_appointments.map do |date, appointments|
        logger.info "[HeywoodHealthcare] Found #{appointments} appointments on #{date}"
        Clinic.new(storage, SITE_NAME, date, appointments, SIGN_UP_URL)
      end
    end
  end

  def self.appointments?
    res = RestClient.get(SIGN_UP_URL)
    if /There are no appointment types available for scheduling/ =~ res
      false
    else
      true
    end
  end

  def self.fetch_appointments
    res = RestClient.post(
      API_URL,
      {
        'type' => '',
        'calendar' => '',
        'skip' => true,
        'options[qty]' => 1,
        'options[numDays]' => 27,
        'ignoreAppointment' => '',
        'appointmentType' => '',
        'calendarID' => '',
      }
    )
    html = Nokogiri::HTML(res.body)
    html.search('.class-signup-container').each_with_object(Hash.new(0)) do |row, h|
      link = row.search('a.btn-class-signup')
      next unless link.any?

      date = Date.parse(link[0]['data-readable-date']).strftime('%m/%d/%Y')
      row.search('.num-slots-available-container .babel-ignore').each do |appointments|
        h[date] += appointments.text.to_i
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :name, :date, :appointments, :link

    def initialize(storage, name, date, appointments, link)
      super(storage)
      @name = name
      @date = date
      @appointments = appointments
      @link = link
    end

    def title
      "#{name} on #{date}"
    end
  end
end
