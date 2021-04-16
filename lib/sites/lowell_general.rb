require 'date'
require 'json'
require 'rest-client'

require_relative '../sentry_helper'
require_relative './base_clinic'

module LowellGeneral
  SIGN_UP_URL = 'https://www.lowellgeneralvaccine.com/'.freeze
  BASE_URL = 'https://lowellgeneralvaccine.myhealthdirect.com'.freeze
  API_URL = "#{BASE_URL}/DataAccess/PageData/ProviderInfo/32122".freeze
  NEXT_URL = "#{BASE_URL}/DecisionSupport/Next".freeze
  WORKFLOW_URL = "#{BASE_URL}/DecisionSupport/Workflow".freeze

  def self.all_clinics(storage, logger)
    logger.info '[LowellGeneral] Checking site'
    SentryHelper.catch_errors(logger, 'LowellGeneral') do
      fetch_appointments(logger)['appointments'].each_with_object(Hash.new(0)) do |appointment, h|
        date, _time = appointment['localSlotDateTimeString'].split(' ')
        h[date] += 1
      end.map do |date, appointments|
        logger.info "[LowellGeneral] Found #{appointments} appointments on #{date}"
        Clinic.new(storage, date, appointments)
      end
    end
  end

  def self.fetch_appointments(logger)
    base_page = RestClient::Request.execute(url: SIGN_UP_URL, method: :get, verify_ssl: false).body
    if /Vaccine appointments are full at this time/ =~ base_page
      logger.info('[LowellGeneral] No vaccine appointments available')
      return { 'appointments' => [] }
    end

    if /Schedule My Appointment/ !~ base_page
      logger.info('[LowellGeneral] No vaccine appointments available')
      return { 'appointments' => [] }
    end

    JSON.parse(
      RestClient.get(
        API_URL,
        params: {
          Month: Date.today.month,
          Year: Date.today.year,
          AppointmentTypeId: 0,
          appointmentStartDateString: '',
          autoAdvance: true,
          days: 30,
        },
        cookies: token_cookies
      ).body
    )
  end

  def self.token_cookies
    page1 = RestClient.get(BASE_URL)
    submit_form1(page1)
    page2 = RestClient.get(WORKFLOW_URL, cookies: page1.cookies)
    submit_form2(page2)
    RestClient.get(WORKFLOW_URL, cookies: page1.cookies)
    page1.cookies
  end

  def self.submit_form1(page)
    html = Nokogiri::HTML(page.body)
    inputs = html.search('form#workboxForm').each_with_object({}) do |form, h|
      form.search('input[type=hidden]').each do |input|
        h[input['name']] = input['value']
      end
      form.search('select').each do |select|
        h[select['name']] = select.search('option')[1]['value']
      end
      form.search('fieldset').each do |fieldset|
        radio = fieldset.search('input')[0]
        h[radio['name']] = radio['value']
      end
    end
    RestClient.post(NEXT_URL, inputs, cookies: page.cookies)
  end

  def self.submit_form2(page)
    html = Nokogiri::HTML(page.body)
    inputs = html.search('form#workboxForm').each_with_object({}) do |form, h|
      form.search('input[type=hidden]').each do |input|
        h[input['name']] = input['value']
      end
      form.search('select').each do |select|
        h[select['name']] = select.search('option')[1]['value']
      end
      form.search('input[type=text]').each do |input|
        h[input['name']] = 'N/A'
      end
      form.search('fieldset').each do |fieldset|
        radio = fieldset.search('input')[1]
        h[radio['name']] = radio['value']
      end
    end
    RestClient.post(NEXT_URL, inputs, cookies: page.cookies)
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments

    def initialize(storage, date, appointments)
      super(storage)
      @date = date
      @appointments = appointments
    end

    def title
      "#{name} on #{date}"
    end

    def name
      'Lowell General Hospital'
    end

    def link
      SIGN_UP_URL
    end

    def address
      '1001 Pawtucket Boulevard East, Lowell MA 01854'
    end
  end
end
