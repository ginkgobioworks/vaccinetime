require_relative '../lib/storage'
require_relative '../lib/sites/cvs'

SIGN_UP_PAGE = 'https://www.cvs.com/immunizations/covid-19-vaccine'

describe Cvs do
  let(:redis) { double('Redis') }
  let(:storage) { Storage.new(redis) }

  describe '.twitter_text' do
    it 'can tweet for one city' do
      clinic = Cvs::StateClinic.new(storage, ['SOMERVILLE'], 'MA')
      expect(clinic.twitter_text).to eq([
        'CVS appointments available in SOMERVILLE. Check eligibility and sign up at https://www.cvs.com/immunizations/covid-19-vaccine'
      ])
    end

    it 'splits up tweets that are too long' do
      clinic = Cvs::StateClinic.new(
        storage,
        ['AMHERST', 'BOSTON', 'BROCKTON', 'CAMBRIDGE', 'CARVER', 'CHICOPEE', 'DANVERS', 'DORCHESTER', 'FALL RIVER', 'FALMOUTH', 'FITCHBURG', 'HAVERHILL', 'LEOMINSTER', 'LUNENBURG', 'LYNN', 'MATTAPAN', 'METHUEN', 'SOMERVILLE', 'SPRINGFIELD', 'WOBURN', 'WORCESTER'],
        'MA'
      )
      expect(clinic.twitter_text).to eq([
        'CVS appointments available in AMHERST, BOSTON, BROCKTON, CAMBRIDGE, CARVER, CHICOPEE, DANVERS, DORCHESTER, FALL RIVER, FALMOUTH, FITCHBURG, HAVERHILL, LEOMINSTER, LUNENBURG, LYNN, MATTAPAN, METHUEN, SOMERVILLE, SPRINGFIELD. Check eligibility and sign up at https://www.cvs.com/immunizations/covid-19-vaccine',
        'CVS appointments available in WOBURN, WORCESTER. Check eligibility and sign up at https://www.cvs.com/immunizations/covid-19-vaccine',
      ])
    end
  end
end
