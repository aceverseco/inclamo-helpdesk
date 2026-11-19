# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inclamo::Ai::InboxChoice do
  let(:account) { create(:account) }
  let!(:website) { create(:inbox, account: account, name: 'Website') }
  let!(:email) { create(:inbox, account: account, name: 'Email') }
  let(:phone) { create(:inbox, account: account, name: 'Phone') }
  let(:our_bot) { create(:agent_bot, account: account) }
  let(:other_bot) { create(:agent_bot, account: account) }

  def choose(ids, **options)
    described_class.inboxes!(account, ids, phone_inbox_id: options.delete(:phone_inbox_id) || phone.id, **options)
  end

  it 'answers the inboxes in the order they were given, once each' do
    expect(choose([email.id, website.id, email.id.to_s])).to eq([email, website])
  end

  it 'refuses an inbox of another account, the Phone inbox and an inbox with another bot or Dialogflow' do
    elsewhere = create(:inbox)
    create(:agent_bot_inbox, inbox: email, agent_bot: other_bot)
    flow = create(:inbox, account: account)
    # Chatwoot gates the integration behind a feature flag the specs need not turn on.
    build(:integrations_hook, :dialogflow, account: account, inbox: flow).save!(validate: false)

    expect { choose([website.id, elsewhere.id]) }.to raise_error(Inclamo::Ai::Error::InvalidInbox)
    expect { choose([website.id, phone.id]) }.to raise_error(Inclamo::Ai::Error::InvalidInbox)
    expect { choose([website.id, email.id]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
    expect { choose([flow.id]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
  end

  describe 'an empty choice' do
    it 'is refused by default, as connecting with a code needs an inbox' do
      expect { choose([]) }.to raise_error(Inclamo::Ai::Error::NoInboxes)
      expect { choose(nil) }.to raise_error(Inclamo::Ai::Error::NoInboxes)
    end

    it 'is no inbox at all when allowed: the agent takes calls only' do
      expect(choose([], allow_empty: true)).to eq([])
    end
  end

  describe "the agent's own bot" do
    before { create(:agent_bot_inbox, inbox: website, agent_bot: our_bot) }

    it 'counts as another bot unless it is named' do
      expect { choose([website.id]) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
      expect(described_class.other_provider(website)).to eq('Agent Bot')
    end

    it 'is free for the bot that is named, and another bot still is not' do
      create(:agent_bot_inbox, inbox: email, agent_bot: other_bot)

      expect(choose([website.id], own_bot_id: our_bot.id)).to eq([website])
      expect(described_class.other_provider(website, our_bot.id)).to be_nil
      expect { choose([website.id, email.id], own_bot_id: our_bot.id) }.to raise_error(Inclamo::Ai::Error::InboxHasBot)
      expect(described_class.other_provider(email, our_bot.id)).to eq('Agent Bot')
    end
  end
end
