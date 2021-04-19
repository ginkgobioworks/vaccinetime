require 'logger'
require_relative '../lib/discord'
require_relative './mock_clinic'

describe DiscordClient do
  let(:discord) { DiscordClient.new(Logger.new('/dev/null')) }

  describe '#discord' do
    it 'calls the discord "update" method' do
      mock_discord = double('Discord')
      mock_clinic = double('Clinic', title: 'Test clinic', new_appointments: 1)
      expect(FakeDiscord).to receive(:new).and_return(mock_discord)
      expect(mock_discord).to receive(:update).with('test message')
      expect(mock_clinic).to receive(:discord_text).and_return('test message')
      discord.message(mock_clinic)
    end
  end

  describe '#should_discord_message?' do
    it 'returns true if the clinic has more than 10 new appointments' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 100)
      expect(mock_clinic.should_discord_message?).to be_truthy
    end

    it 'returns false if the clinic has no link' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 100, link: nil)
      expect(mock_clinic.should_discord_message?).to be_falsy
    end

    it 'returns false if the clinic has fewer than 10 appointments' do
      mock_clinic = MockClinic.new(appointments: 9, new_appointments: 100)
      expect(mock_clinic.should_discord_message?).to be_falsy
    end

    it 'returns false if the clinic has fewer than 5 new appointments' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 4)
      expect(mock_clinic.should_discord_message?).to be_falsy
    end

    it 'returns false if the clinic has posted recently' do
      mock_clinic = MockClinic.new(appointments: 100, new_appointments: 100, last_posted_time: (Time.now - 60).to_s)
      expect(mock_clinic.should_discord_message?).to be_falsy
    end
  end

  describe '#post' do
    it 'only sends about clinics that should post' do
      valid_clinic = MockClinic.new(appointments: 100, new_appointments: 100)
      invalid_clinic = MockClinic.new(appointments: 0, new_appointments: 0)
      expect(discord).to receive(:message).with(valid_clinic)
      expect(discord).not_to receive(:message).with(invalid_clinic)
      expect(valid_clinic).to receive(:save_message_time)
      expect(invalid_clinic).not_to receive(:save_message_time)
      discord.post([valid_clinic, invalid_clinic])
    end

    it "doesn't care about the clinic order" do
      valid_clinic = MockClinic.new(appointments: 100, new_appointments: 100)
      invalid_clinic = MockClinic.new(appointments: 0, new_appointments: 0)
      expect(discord).to receive(:message).with(valid_clinic)
      expect(discord).not_to receive(:message).with(invalid_clinic)
      expect(valid_clinic).to receive(:save_message_time)
      expect(invalid_clinic).not_to receive(:save_message_time)
      discord.post([invalid_clinic, valid_clinic])
    end

    it 'works with no clinics' do
      expect { discord.post([]) }.not_to raise_exception
    end
  end

  describe '#discord_text' do
    it 'posts about appointments with a link' do
      mock_clinic = MockClinic.new(title: 'myclinic', appointments: 100, new_appointments: 20)
      expect(mock_clinic.discord_text).to eq(
        '100 appointments available at myclinic. Check eligibility and sign up at clinicsite.com'
      )
    end
  end
end
