require 'logger'
require_relative '../lib/twitter'
require_relative './mock_clinic'

describe TwitterClient do
  let(:twitter) { TwitterClient.new(Logger.new('/dev/null')) }

  describe '#tweet' do
    it 'calls the twitter "update" method' do
      mock_twitter = double('Twitter')
      mock_clinic = double('Clinic', title: 'Test clinic', new_appointments: 1)
      expect(FakeTwitter).to receive(:new).and_return(mock_twitter)
      expect(mock_twitter).to receive(:update).with('test tweet')
      expect(mock_clinic).to receive(:twitter_text).and_return('test tweet')
      twitter.tweet(mock_clinic)
    end
  end

  describe '#should_post?' do
    it 'returns true if the clinic has more than 10 new appointments' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 100)
      expect(twitter.should_post?(mock_clinic)).to be_truthy
    end

    it 'returns false if the clinic has no link' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 100, link: nil)
      expect(twitter.should_post?(mock_clinic)).to be_falsy
    end

    it 'returns false if the clinic has fewer than 10 appointments' do
      mock_clinic = MockClinic.new(appointments: 9, new_appointments: 100)
      expect(twitter.should_post?(mock_clinic)).to be_falsy
    end

    it 'returns false if the clinic has fewer than 5 new appointments' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 4)
      expect(twitter.should_post?(mock_clinic)).to be_falsy
    end

    it 'returns false if the clinic has posted recently' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 100, last_posted_time: (Time.now - 60).to_s)
      expect(twitter.should_post?(mock_clinic)).to be_falsy
    end
  end

  describe '#post' do
    it 'only tweets about clinics that should post' do
      valid_clinic = MockClinic.new(appointments: 100, new_appointments: 100)
      invalid_clinic = MockClinic.new(appointments: 0, new_appointments: 0)
      expect(twitter).to receive(:tweet).with(valid_clinic)
      expect(twitter).not_to receive(:tweet).with(invalid_clinic)
      expect(valid_clinic).to receive(:save_tweet_time)
      expect(invalid_clinic).not_to receive(:save_tweet_time)
      twitter.post([valid_clinic, invalid_clinic])
    end

    it "doesn't care about the clinic order" do
      valid_clinic = MockClinic.new(appointments: 100, new_appointments: 100)
      invalid_clinic = MockClinic.new(appointments: 0, new_appointments: 0)
      expect(twitter).to receive(:tweet).with(valid_clinic)
      expect(twitter).not_to receive(:tweet).with(invalid_clinic)
      expect(valid_clinic).to receive(:save_tweet_time)
      expect(invalid_clinic).not_to receive(:save_tweet_time)
      twitter.post([invalid_clinic, valid_clinic])
    end

    it 'works with no clinics' do
      expect { twitter.post([]) }.not_to raise_exception
    end
  end
end
