require_relative '../lib/storage'
require_relative '../lib/twitter'
require_relative '../lib/sites/ma_immunizations'

describe 'MaImmunizations' do
  let(:redis) { double('Redis') }
  let(:logger) { Logger.new('/dev/null') }
  let(:fixture) { File.read("#{__dir__}/fixtures/ma_immunizations.html") }
  let(:storage) { Storage.new(redis) }

  describe '.all_clinics' do
    it 'returns all clinics' do
      expect(redis).to receive(:get).with('vaccine-cookies:ma-immunization').and_return({ cookies: 'foo', expiration: Time.now + (60 * 60 * 24) }.to_json)
      response = double('RestClient::Response', body: fixture)
      expect(RestClient).to receive(:get).and_return(response)
      clinics = MaImmunizations.all_clinics(storage, logger)
      # NOTE(dan): there are 8 clinics in the example file but one is a
      # duplicate that we consolidate, so we only expect to have 7
      expect(clinics.length).to eq(3)
      first_clinic = clinics[0]
      expect(first_clinic.appointments).to eq(124)
      expect(first_clinic.title).to eq('Citizen Center on 05/13/2021')
    end

    it 'can work with twitter' do
      mock_twitter = double('Twitter')
      expect(FakeTwitter).to receive(:new).and_return(mock_twitter)
      twitter = TwitterClient.new(logger)
      response = double('RestClient::Response', body: fixture)
      expect(RestClient).to receive(:get).and_return(response)
      expect(redis).to receive(:get).with('vaccine-cookies:ma-immunization').and_return({ cookies: 'foo', expiration: Time.now + (60 * 60 * 24) }.to_json)
      clinics = MaImmunizations.all_clinics(storage, logger)
      allow(redis).to receive(:get).and_return(nil)
      allow(redis).to receive(:set)
      expect(mock_twitter).to receive(:update).with('124 appointments available at Citizen Center in Haverhill, MA on 05/13/2021 for Moderna COVID-19 Vaccine, Janssen COVID-19 Vaccine. Check eligibility and sign up at https://www.maimmunizations.org/appointment/en/clinic/search?q[venue_search_name_or_venue_name_i_cont]=Citizen%20Center&')
      expect(mock_twitter).to receive(:update).with('23 appointments available at Citizen Center in Haverhill, MA on 05/20/2021 for Moderna COVID-19 Vaccine. Check eligibility and sign up at https://www.maimmunizations.org/appointment/en/clinic/search?q[venue_search_name_or_venue_name_i_cont]=Citizen%20Center&')
      expect(mock_twitter).to receive(:update).with('79 appointments available at Citizen Center in Haverhill, MA on 05/27/2021 for Moderna COVID-19 Vaccine. Check eligibility and sign up at https://www.maimmunizations.org/appointment/en/clinic/search?q[venue_search_name_or_venue_name_i_cont]=Citizen%20Center&')
      twitter.post(clinics)
    end
  end
end
