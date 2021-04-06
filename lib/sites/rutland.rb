require 'rest-client'

require_relative '../sentry_helper'
require_relative './ma_immunizations_registrations'

module Rutland
  BASE_URL = 'https://www.rrecc.us/k12'.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Rutland] Checking site'
    SentryHelper.catch_errors(logger, 'Rutland') do
      res = RestClient.get(BASE_URL).body
      sites = res.scan(%r{www\.maimmunizations\.org__reg_(\d+)&})
      if sites.empty?
        logger.info '[Rutland] No sites found'
      else
        logger.info "[Rutland] #{sites.length} sites found"
        MaImmunizationsRegistrations.all_clinics(
          BASE_URL,
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
