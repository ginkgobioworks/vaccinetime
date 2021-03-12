require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module MyChart
  SITES = {
    'UMass Memorial' => {
      token_url: 'https://mychartonline.umassmemorial.org/mychart/openscheduling?specialty=15&hidespecialtysection=1',
      scheduling_api_url: 'https://mychartonline.umassmemorial.org/MyChart/OpenScheduling/OpenScheduling/GetScheduleDays',
      providers: %w[56394 56395 56396 56475 56476 56477 56526 56527 56528 56529 56530 56531 56554 56584 56596 57002 57003],
      departments: %w[104001144 111029146 111029148],
      sign_up_page: 'https://mychartonline.umassmemorial.org/mychart/openscheduling?specialty=15&hidespecialtysection=1',
    },
    'SBCHC' => {
      token_url: 'https://mychartos.ochin.org/mychart/SignupAndSchedule/EmbeddedSchedule?id=1900119&dept=150001007&vt=1089&payor=-1,-2,-3,4653,1624,4660,4655,1292,4881,5543,5979,2209,5257,1026,1001,2998,3360,3502,4896,2731',
      scheduling_api_url: 'https://mychartos.ochin.org/mychart/OpenScheduling/OpenScheduling/GetScheduleDays',
      providers: %w[1900119],
      departments: %w[150001007],
      sign_up_page: 'https://forms.office.com/Pages/ResponsePage.aspx?id=J8HP3h4Z8U-yP8ih3jOCukT-1W6NpnVIp4kp5MOEapVUOTNIUVZLODVSMlNSSVc2RlVMQ1o1RjNFUy4u',
    },
    'BMC' => {
      token_url: 'https://mychartscheduling.bmc.org/mychartscheduling/SignupAndSchedule/EmbeddedSchedule',
      scheduling_api_url: 'https://mychartscheduling.bmc.org/MyChartscheduling/OpenScheduling/OpenScheduling/GetScheduleDays',
      providers: %w[10033319 10033364 10033367 10033370 10033373],
      departments: %w[10098241 10098242 10098243 10098244 10098245],
      sign_up_page: 'https://www.bmc.org/covid-19-vaccine-locations',
    },
  }.freeze

  def self.all_clinics(storage, logger)
    SITES.flat_map do |name, config|
      sleep(2)
      SentryHelper.catch_errors(logger, 'MyChart') do
        logger.info "[MyChart] Checking site #{name}"
        Page.new(name, config, storage, logger).clinics
      end
    end
  end

  class Page
    def initialize(name, config, storage, logger)
      @name = name
      @config = config
      @storage = storage
      @logger = logger
      @json = appointments_json
    end

    def credentials
      response = RestClient.get(@config[:token_url])
      cookies = response.cookies
      doc = Nokogiri::HTML(response)
      token = doc.search('input[name=__RequestVerificationToken]')[0]['value']
      {
        cookies: cookies,
        '__RequestVerificationToken' => token,
      }
    end

    def appointments_json
      params = {
        'view' => 'grouped',
        'specList' => '15',
        'vtList' => '5060',
        'start' => Time.now.strftime('%Y-%m-%d'),
        'filters' => {
          #'Providers' => @config[:providers].map { |p| [p, true] }.to_h,
          #'Departments' => @config[:departments].map { |d| [d, true] }.to_h,
          #'DaysOfWeek' => (0..6).map { |d| [d, true] }.to_h,
          'Providers' => {},
          'Departments' => {},
          'DaysOfWeek' => {},
          'TimesOfDay': 'both',
        },
      }
      res = RestClient.post(@config[:scheduling_api_url], params, credentials)
      JSON.parse(res.body)
    end

    def clinics
      slots = {}
      deps = departments

      @json['ByDateThenProviderCollated'].each do |date, date_info|
        date_info['ProvidersAndHours'].each do |_provider, provider_info|
          provider_info['DepartmentAndSlots'].each do |department, department_info|
            department_info['HoursAndSlots'].each do |_hour, hour_info|
              slots[date] ||= { site: deps[department], slots: 0 }
              slots[date][:slots] += hour_info['Slots'].length
            end
          end
        end
      end

      slots.map do |date, info|
        @logger.info "[MyChart] Site #{info[:site]} on #{date}: found #{info[:slots]} appointments"
        Clinic.new(info[:site], date, info[:slots], @config[:sign_up_page], @logger, @storage)
      end
    end

    def departments
      @json['AllDepartments'].transform_values do |info|
        info['Name']
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :site, :date, :appointments, :link

    def initialize(site, date, appointments, link, logger, storage)
      super(storage)
      @site = site
      @date = date
      @appointments = appointments
      @link = link
      @logger = logger
    end

    def title
      "#{@site} on #{@date}"
    end

    def sign_up_page
      link
    end
  end
end