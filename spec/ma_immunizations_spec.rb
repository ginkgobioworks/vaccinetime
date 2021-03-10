require_relative '../lib/storage'
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
      expect(clinics.length).to eq(7)
      first_clinic = clinics[0]
      expect(first_clinic.appointments).to eq(100)
      expect(first_clinic.title).to eq('Reggie Lewis State Track Athletic Ctr, Tremont Street, Boston, MA, USA on 03/01/2021')
    end

    it 'can work with twitter' do
      mock_twitter = double('Twitter')
      expect(FakeTwitter).to receive(:new).and_return(mock_twitter)
      twitter = TwitterClient.new(logger)
      response = double('RestClient::Response', body: fixture)
      expect(RestClient).to receive(:get).and_return(response)
      expect(redis).to receive(:get).with('vaccine-cookies:ma-immunization').and_return({ cookies: 'foo', expiration: Time.now + (60 * 60 * 24) }.to_json)
      clinics = MaImmunizations.all_clinics(storage, logger)
      expect(redis).to receive(:get).exactly(3).times.and_return(nil)
      expect(redis).to receive(:set).once
      expect(mock_twitter).to receive(:update).with('100 appointments available at Reggie Lewis State Track Athletic Ctr, Tremont Street, Boston, MA, USA on 03/01/2021. Check eligibility and sign up at https://www.maimmunizations.org/clinic/search?q[venue_search_name_or_venue_name_i_cont]=Reggie%20Lewis%20State%20Track%20Athletic%20Ctr,%20Tremont%20Street,%20Boston,%20MA,%20USA&')
      twitter.post(clinics)
    end
  end
end
