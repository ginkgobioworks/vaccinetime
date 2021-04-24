require 'rest-client'

require_relative '../sentry_helper'
require_relative './ma_immunizations_registrations'

module Rutland
  MAIN_URL = 'https://www.rrecc.us/vaccine'.freeze
  TEACHER_URL = 'https://www.rrecc.us/k12'.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Rutland] Checking site'
    main_clinics(storage, logger) #+ teacher_clinics(storage, logger)
  end

  def self.main_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Rutland') do
      res = RestClient.get(MAIN_URL).body

      sections = res.split('<span style="text-decoration:underline;"')

      sections.flat_map do |section|
        additional_info = if section.start_with?('>')
                            match = />([\w\d\s-]+)[<(]/.match(section)
                            match && match[1].strip
                          end

        sites = section.scan(%r{www\.maimmunizations\.org//reg/(\d+)"})
        if sites.empty?
          logger.info '[Rutland] No sites found'
          []
        else
          logger.info "[Rutland] Scanning #{sites.length} sites"
          MaImmunizationsRegistrations.all_clinics(
            'RUTLAND',
            MAIN_URL,
            sites.map { |clinic_num| "https://registrations.maimmunizations.org//reg/#{clinic_num[0]}" },
            storage,
            logger,
            'Rutland',
            additional_info
          )
        end
      end
    end
  end

  def self.teacher_clinics(storage, logger)
    SentryHelper.catch_errors(logger, 'Rutland') do
      res = RestClient.get(TEACHER_URL).body
      sites = res.scan(%r{www\.maimmunizations\.org__reg_(\d+)&})
      if sites.empty?
        logger.info '[Rutland] No sites found'
        []
      else
        logger.info "[Rutland] Scanning #{sites.length} sites"
        MaImmunizationsRegistrations.all_clinics(
          'RUTLAND',
          TEACHER_URL,
          sites.map { |clinic_num| "https://registrations.maimmunizations.org//reg/#{clinic_num[0]}" },
          storage,
          logger,
          'Rutland',
          'teachers only'
        )
      end
    end
  end
end
