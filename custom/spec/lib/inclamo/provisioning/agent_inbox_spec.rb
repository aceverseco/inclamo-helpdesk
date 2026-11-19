# frozen_string_literal: true

require 'rails_helper'

# Where the agent starts when the store app connects it (design D4): the
# provisioned account's storefront inbox, or none.
RSpec.describe Inclamo::Provisioning::AgentInbox do
  let(:account) { create(:account) }
  let!(:storefront) { create(:inbox, account: account, name: 'Storefront') }
  let!(:row) { Inclamo::ProvisionedAccount.create!(shop_domain: 'example-store.myshopify.com', account: account, state: 'active', storefront_inbox: storefront) }

  def without_the_column
    connection = Inclamo::ProvisionedAccount.connection
    allow(connection).to receive(:column_exists?).and_call_original
    allow(connection).to receive(:column_exists?).with('inclamo_provisioned_accounts', 'storefront_inbox_id').and_return(false)
  end

  it 'answers the storefront inbox the store row names' do
    expect(described_class.for(account)).to eq(storefront)
  end

  it 'answers it among other inboxes of the account, and only it' do
    create(:inbox, account: account, name: 'Second site')
    create(:inbox, :with_email, account: account)

    expect(described_class.for(account)).to eq(storefront)
  end

  it 'answers none when the row names no inbox' do
    row.update!(storefront_inbox: nil)

    expect(described_class.for(account)).to be_nil
  end

  it 'answers none once the inbox is gone' do
    storefront.destroy!

    expect(row.reload.storefront_inbox_id).to be_nil
    expect(described_class.for(account)).to be_nil
  end

  it 'answers none when the inbox named is not a website inbox of this account' do
    api_inbox = create(:channel_api, account: account).inbox
    row.update_column(:storefront_inbox_id, api_inbox.id) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.for(account)).to be_nil

    foreign = create(:inbox)
    row.update_column(:storefront_inbox_id, foreign.id) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.for(account)).to be_nil
  end

  it 'answers none when the inbox has another bot' do
    create(:agent_bot_inbox, inbox: storefront, agent_bot: create(:agent_bot, account: account))

    expect(described_class.for(account)).to be_nil
  end

  it 'answers none when the inbox has a Dialogflow bot' do
    create(:integrations_hook, :dialogflow, account: account, inbox: storefront)

    expect(described_class.for(account)).to be_nil
  end

  it 'answers none for an account the store app did not provision' do
    expect(described_class.for(create(:account))).to be_nil
  end

  describe 'on an installation without the storefront chat' do
    it 'answers none, whatever the store row holds, and asks the database nothing else about it' do
      without_the_column
      expect(Inclamo::ProvisionedAccount).not_to receive(:where)

      expect(described_class.for(account)).to be_nil
    end

    it 'asks the database whether the column is there, not a cached list of columns' do
      expect(described_class.column?).to be(true)
      without_the_column
      expect(described_class.column?).to be(false)
    end
  end
end
