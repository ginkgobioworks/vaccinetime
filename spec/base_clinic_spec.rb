require 'date'

require_relative '../lib/sites/base_clinic'

describe BaseClinic do
  let(:redis) { double('Redis') }
  let(:storage) { Storage.new(redis) }

  describe '#last_appointments' do
    it 'gets last appointments from storage' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(10)
      expect(clinic.last_appointments).to eq(10)
    end

    it 'returns 0 if nothing is in storage' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(nil)
      expect(clinic.last_appointments).to eq(0)
    end
  end

  describe '#new_appointments' do
    it 'returns the difference in appointments since last check' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(10)
      allow(clinic).to receive(:appointments).and_return(15)
      expect(clinic.new_appointments).to eq(5)
    end

    it 'can return negative numbers' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(10)
      allow(clinic).to receive(:appointments).and_return(5)
      expect(clinic.new_appointments).to eq(-5)
    end
  end

  describe '#render_slack_appointments' do
    it 'includes new appointments' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(5)
      allow(clinic).to receive(:appointments).and_return(8)
      expect(clinic.render_slack_appointments).to eq('8 (3 new)')
    end

    it 'renders sirens if over 10 appointments' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(5)
      allow(clinic).to receive(:appointments).and_return(11)
      expect(clinic.render_slack_appointments).to eq(':siren: 11 (6 new) :siren:')
    end
  end

  describe '#slack_blocks' do
    it 'formats a message for slack' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_appointments).with(clinic).and_return(5)
      allow(clinic).to receive(:title).and_return('Base clinic on 4/10/21')
      allow(clinic).to receive(:link).and_return('foo.com')
      allow(clinic).to receive(:appointments).and_return(12)
      expect(clinic.slack_blocks).to eq({
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: "*Base clinic on 4/10/21*\n*Available appointments:* :siren: 12 (7 new) :siren:\n*Link:* foo.com",
        },
      })
    end
  end

  describe '#has_not_posted_recently?' do
    it 'returns true if there are no previous posts' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_post_time).with(clinic).and_return(nil)
      expect(clinic.has_not_posted_recently?).to be true
    end

    it 'returns true if no posts in the last 30 minutes' do
      clinic = BaseClinic.new(storage)
      allow(storage).to receive(:get_post_time).with(clinic).and_return((Time.now - 40 * 60).to_s)
      expect(clinic.has_not_posted_recently?).to be true
    end

    it 'returns false if there is a post in the last 10 minutes' do
      clinic = BaseClinic.new(storage)
      expect(storage).to receive(:get_post_time).with(clinic).and_return((Time.now - 5 * 60).to_s)
      expect(clinic.has_not_posted_recently?).to be false
    end
  end

  describe '#should_tweet' do
    it "returns true if there's a link and enough appointments" do
      clinic = BaseClinic.new(storage)
      allow(clinic).to receive(:link).and_return('foo.com')
      allow(clinic).to receive(:appointments).and_return(50)
      allow(storage).to receive(:get_appointments).and_return(10)
      allow(storage).to receive(:get_post_time).and_return(nil)
      expect(clinic.should_tweet?).to be true
    end

    it "returns false if there's no link" do
      clinic = BaseClinic.new(storage)
      allow(clinic).to receive(:link).and_return(nil)
      allow(clinic).to receive(:appointments).and_return(50)
      allow(storage).to receive(:get_appointments).and_return(10)
      allow(storage).to receive(:get_post_time).and_return(nil)
      expect(clinic.should_tweet?).to be false
    end

    it "returns false if there's not enough appointments" do
      clinic = BaseClinic.new(storage)
      allow(clinic).to receive(:link).and_return('foo.com')
      allow(clinic).to receive(:appointments).and_return(5)
      allow(storage).to receive(:get_appointments).and_return(0)
      allow(storage).to receive(:get_post_time).and_return(nil)
      expect(clinic.should_tweet?).to be false
    end

    it "returns false if there's not enough new appointments" do
      clinic = BaseClinic.new(storage)
      allow(clinic).to receive(:link).and_return('foo.com')
      allow(clinic).to receive(:appointments).and_return(50)
      allow(storage).to receive(:get_appointments).and_return(49)
      allow(storage).to receive(:get_post_time).and_return(nil)
      expect(clinic.should_tweet?).to be false
    end

    it "returns false if there's been a tweet recently" do
      clinic = BaseClinic.new(storage)
      allow(clinic).to receive(:link).and_return('foo.com')
      allow(clinic).to receive(:appointments).and_return(50)
      allow(storage).to receive(:get_appointments).and_return(0)
      allow(storage).to receive(:get_post_time).and_return((Time.now - 60).to_s)
      expect(clinic.should_tweet?).to be false
    end
  end
end
