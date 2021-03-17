require 'nokogiri'

require_relative '../sentry_helper'
require_relative './base_clinic'

module MyChart
  SITES = {
    'UMass Memorial' => {
      token_url: 'https://mychartonline.umassmemorial.org/mychart/openscheduling?specialty=15&hidespecialtysection=1',
      scheduling_api_url: 'https://mychartonline.umassmemorial.org/MyChart/OpenScheduling/OpenScheduling/GetScheduleDays',
      api_payload: {
        'view' => 'grouped',
        'specList' => '15',
        'vtList' => '5060',
        'start' => '',
        'filters' => {
          'Providers' => {},
          'Departments' => {},
          'DaysOfWeek' => {},
          'TimesOfDay': 'both',
        },
      },
      sign_up_page: 'https://mychartonline.umassmemorial.org/mychart/openscheduling?specialty=15&hidespecialtysection=1',
    },

    'SBCHC' => {
      token_url: 'https://mychartos.ochin.org/mychart/SignupAndSchedule/EmbeddedSchedule?id=1900119&dept=150001007&vt=1089&payor=-1,-2,-3,4653,1624,4660,4655,1292,4881,5543,5979,2209,5257,1026,1001,2998,3360,3502,4896,2731',
      scheduling_api_url: 'https://mychartos.ochin.org/mychart/OpenScheduling/OpenScheduling/GetOpeningsForProvider',
      api_payload: {
        'id' => '1900119',
        'vt' => '1089',
        'dept' => '150001007',
        'view' => 'grouped',
        'start' => '',
        'filters' => {
          'Providers' => {},
          'Departments' => {},
          'DaysOfWeek' => {},
          'TimesOfDay': 'both',
        },
      },
      sign_up_page: 'https://forms.office.com/Pages/ResponsePage.aspx?id=J8HP3h4Z8U-yP8ih3jOCukT-1W6NpnVIp4kp5MOEapVUOTNIUVZLODVSMlNSSVc2RlVMQ1o1RjNFUy4u',
    },

    'BMC' => {
      token_url: 'https://mychartscheduling.bmc.org/mychartscheduling/SignupAndSchedule/EmbeddedSchedule',
      scheduling_api_url: 'https://mychartscheduling.bmc.org/MyChartscheduling/OpenScheduling/OpenScheduling/GetOpeningsForProvider',
      api_payload: {
        'id' => '10033319,10033364,10033367,10033370,10033706,10033373',
        'vt' => '2008',
        'dept' => '10098245,10098242,10098243,10098244,10108801,10098241',
        'view' => 'grouped',
        'start' => '',
        'filters' => {
          'Providers' => {},
          'Departments' => {},
          'DaysOfWeek' => {},
          'TimesOfDay': 'both',
        },
      },
      sign_up_page: 'https://mychartscheduling.bmc.org/MyChartscheduling/covid19#/',
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
      res = RestClient.post(
        "#{@config[:scheduling_api_url]}?noCache=#{Time.now.to_i}",
        @config[:api_payload],
        credentials
      )
      JSON.parse(res.body)
    end

    def clinics
      slots = {}

      @json['ByDateThenProviderCollated'].each do |date, date_info|
        date_info['ProvidersAndHours'].each do |_provider, provider_info|
          provider_info['DepartmentAndSlots'].each do |department, department_info|
            department_info['HoursAndSlots'].each do |_hour, hour_info|
              slots[date] ||= { department: @json['AllDepartments'][department], slots: 0 }
              slots[date][:slots] += hour_info['Slots'].length
            end
          end
        end
      end

      slots.map do |date, info|
        @logger.info "[MyChart] Site #{info[:department]['Name']} on #{date}: found #{info[:slots]} appointments"
        Clinic.new(info[:department], date, info[:slots], @config[:sign_up_page], @logger, @storage)
      end
    end
  end

  class Clinic < BaseClinic
    attr_reader :date, :appointments, :link

    def initialize(department, date, appointments, link, logger, storage)
      super(storage)
      @department = department
      @date = date
      @appointments = appointments
      @link = link
      @logger = logger
    end

    def name
      @department['Name']
    end

    def address
      "#{@department['Address']['Street'].join(' ')}, #{city}, MA"
    end

    def city
      @department['Address']['City'].split.map(&:capitalize).join(' ')
    end

    def title
      "#{name} on #{@date}"
    end

    def sign_up_page
      link
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

    def twitter_text
      txt = "#{appointments} appointments available at #{name}"
      txt += " in #{city} MA" if city
      txt + " on #{date}. Check eligibility and sign up at #{sign_up_page}"
    end
  end
end
