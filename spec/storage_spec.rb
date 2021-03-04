require_relative '../lib/storage'

describe Storage do
  describe '#with_prefix' do
    it 'uses a prefix plus storage key' do
      mock_clinic = double('Clinic', storage_key: 'example clinic')
      storage = Storage.new
      expect(storage.with_prefix('my-prefix', mock_clinic)).to eq('my-prefix:example clinic')
    end
  end

  describe '#set' do
    it 'saves directly to redis' do
      mock_redis = double('Redis')
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      expect(mock_redis).to receive(:set).with('foo', 'bar')
      storage.set('foo', 'bar')
    end
  end

  describe '#get' do
    it 'fetches from redis' do
      mock_redis = double('Redis')
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      expect(mock_redis).to receive(:get).with('foo').and_return('bar')
      expect(storage.get('foo')).to eq('bar')
    end
  end

  describe '#save_appointments' do
    it 'saves appointments using a storage key' do
      mock_clinic = double('Clinic', storage_key: 'example clinic', appointments: 7)
      mock_redis = double('Redis')
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      expect(mock_redis).to receive(:set).with('slack-vaccine-appt:example clinic', 7)
      storage.save_appointments(mock_clinic)
    end
  end

  describe '#get_appointments' do
    it 'gets appointments using a storage key' do
      mock_clinic = double('Clinic', storage_key: 'example clinic', appointments: 7)
      mock_redis = double('Redis')
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      expect(mock_redis).to receive(:get).with('slack-vaccine-appt:example clinic').and_return(5)
      expect(storage.get_appointments(mock_clinic)).to eq(5)
    end
  end

  describe '#save_post_time' do
    it 'saves post time using a storage key' do
      mock_clinic = double('Clinic', storage_key: 'example clinic', appointments: 7)
      mock_redis = double('Redis')
      now = Time.now
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      expect(Time).to receive(:now).and_return(now)
      expect(mock_redis).to receive(:set).with('slack-vaccine-post:example clinic', now)
      storage.save_post_time(mock_clinic)
    end
  end

  describe '#get_post_time' do
    it 'gets the post time using a storage key' do
      mock_clinic = double('Clinic', storage_key: 'example clinic', appointments: 7)
      mock_redis = double('Redis')
      now = Time.now
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      expect(mock_redis).to receive(:get).with('slack-vaccine-post:example clinic').and_return(now)
      expect(storage.get_post_time(mock_clinic)).to eq(now)
    end
  end

  describe '#save_cookies' do
    it 'saves cookies to redis' do
      mock_redis = double('Redis')
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      now = DateTime.now
      expect(mock_redis).to receive(:set).with('vaccine-cookies:ma-immunization', { 'cookies' => 'foo', 'expiration' => now }.to_json)
      storage.save_cookies('ma-immunization', 'foo', now)
    end
  end

  describe '#get_cookies' do
    it 'gets cookies from storage' do
      mock_redis = double('Redis')
      expect(Redis).to receive(:new).and_return(mock_redis)
      storage = Storage.new
      now = DateTime.now
      expect(mock_redis).to receive(:get).with('vaccine-cookies:ma-immunization').and_return({ 'cookies' => 'foo', 'expiration' => now }.to_json)
      res = storage.get_cookies('ma-immunization')
      expect(res['cookies']).to eq('foo')
      expect(res['expiration']).to eq(now.to_s)
    end
  end
end
