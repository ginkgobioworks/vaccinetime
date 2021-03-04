require 'logger'
require_relative '../lib/slack'

describe SlackClient do
  describe '#send' do
    it 'sends a slack' do
      mock_slack = double('Slack::Web::Client')
      mock_clinic = double('Clinic', title: 'Test clinic', new_appointments: 1)
      expect(FakeSlack).to receive(:new).and_return(mock_slack)
      expect(mock_slack).to receive(:chat_postMessage).with(
        blocks: ['test blocks'],
        channel: '#bot-vaccine',
        username: 'vaccine-bot',
        icon_emoji: ':old-man-yells-at-covid19:'
      )
      expect(mock_clinic).to receive(:slack_blocks).and_return('test blocks')
      slack = SlackClient.new(Logger.new('/dev/null'))
      slack.send([mock_clinic])
    end
  end
end
