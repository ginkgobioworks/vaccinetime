require 'rest-client'

require_relative '../sentry_helper'
require_relative './ma_immunizations_registrations'

module Amesbury
  BASE_URL = 'https://www.amesburyma.gov/home/urgent-alerts/covid-19-vaccine-distribution'.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Amesbury] Checking site'
    SentryHelper.catch_errors(logger, 'Amesbury') do
      res = RestClient.get(BASE_URL).body
      sites = res.scan(%r{https://www\.(maimmunizations\.org/+reg/\d+)})
      if sites.empty?
        logger.info '[Amesbury] No sites found'
        []
      else
        logger.info "[Amesbury] Scanning #{sites.length} sites"
        MaImmunizationsRegistrations.all_clinics(
          BASE_URL,
          sites.map { |clinic_url| "https://registrations.#{clinic_url[0]}" },
          storage,
          logger,
          'Amesbury'
        )
      end
    end
  end
end
