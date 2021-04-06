require 'rest-client'

require_relative '../sentry_helper'
require_relative './ma_immunizations_registrations'

module Northampton
  BASE_URL = 'https://www.northamptonma.gov/2219/Vaccine-Clinics'.freeze

  def self.all_clinics(storage, logger)
    logger.info '[Northampton] Checking site'
    SentryHelper.catch_errors(logger, 'Northampton') do
      res = RestClient.get(BASE_URL).body
      sites = res.scan(%r{https://www\.(maimmunizations\.org//reg/\d+)})
      if sites.empty?
        logger.info '[Northampton] No sites found'
      else
        logger.info "[Northampton] #{sites.length} sites found"
        MaImmunizationsRegistrations.all_clinics(
          BASE_URL,
          sites.map { |clinic_url| "https://registrations.#{clinic_url[0]}" },
          storage,
          logger,
          'Northampton'
        )
      end
    end
  end
end
