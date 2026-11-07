# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe Inclamo::Shopify::ConversationOrder do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact, custom_attributes: { 'priority_note' => 'vip' }) }
  let(:marker) { described_class.new(conversation) }
  let(:shipped) { shopify_fixture('order_details_shipped')['order'] }
  let(:open_order) { shopify_fixture('order_details_open')['order'] }

  before { Inclamo::Shopify::OrderReader.forget!(account.id) }

  describe 'marking by hand' do
    it 'writes the number, statuses, first tracking number and links, and never the address' do
      marker.mark!(shipped)

      attributes = conversation.reload.custom_attributes
      expect(attributes).to include(
        'shopify_order_number' => '#1002', 'shopify_order_payment_status' => 'paid', 'shopify_order_fulfillment_status' => 'fulfilled',
        'shopify_order_tracking_number' => 'E2Et001A', 'shopify_order_tracking_link' => 'https://example.com/track/E2Et001A'
      )
      expect(attributes['shopify_order_admin_link']).to match(%r{\Ahttps://admin\.shopify\.com/store/example-store/orders/\d+\z})
      expect(attributes.to_json).not_to match(/Springfield|Example Street|62701|Maya/)
      expect(attributes['priority_note']).to eq('vip')
    end

    it 'replaces the attributes when another order is marked, leaving none of the first' do
      marker.mark!(shipped)
      marker.mark!(open_order)

      attributes = conversation.reload.custom_attributes
      expect(attributes['shopify_order_number']).to eq('#1001')
      expect(attributes).not_to include('shopify_order_tracking_number', 'shopify_order_tracking_link')
    end

    it 'clears the mark and keeps the other attributes of the conversation' do
      marker.mark!(shipped)
      marker.clear!

      expect(conversation.reload.custom_attributes).to eq('priority_note' => 'vip')
    end

    it 'keeps what was set on the conversation while the store was being read' do
      loaded = Conversation.find(conversation.id)
      Conversation.find(conversation.id).update!(custom_attributes: conversation.custom_attributes.merge('set_by_a_rule' => 'yes'))

      described_class.new(loaded).mark!(shipped)
      expect(conversation.reload.custom_attributes).to include('set_by_a_rule' => 'yes', 'priority_note' => 'vip', 'shopify_order_number' => '#1002')

      stale = Conversation.find(conversation.id)
      Conversation.find(conversation.id).update!(custom_attributes: conversation.custom_attributes.merge('set_later' => 'yes'))
      described_class.new(stale).clear!
      expect(conversation.reload.custom_attributes).to eq('priority_note' => 'vip', 'set_by_a_rule' => 'yes', 'set_later' => 'yes')
    end

    it 'writes nothing when nothing changed' do
      marker.mark!(shipped)

      expect { marker.mark!(shipped) }.not_to(change { conversation.reload.updated_at })
    end
  end

  describe 'marking from the first message' do
    before do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
    end

    it 'marks the order the customer names when it is their own' do
      stub_shopify(:orders_by_number, data: { orders: { nodes: [open_order] } })

      marker.auto_mark!('Hi, where is my order #1001? It has been a week.')

      expect(conversation.reload.custom_attributes['shopify_order_number']).to eq('#1001')
    end

    it 'does not mark an order of someone else' do
      stub_shopify_fixture(:orders_by_number, 'orders_by_number_others')

      expect(marker.auto_mark!('Please check order 1004 for me')).to be_nil
      expect(conversation.reload.custom_attributes).not_to include('shopify_order_number')
    end

    it 'asks the store nothing when the message has no number' do
      marker.auto_mark!('Hello, I have a question about sizes')

      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end

    it 'leaves an order marked by an agent alone' do
      marker.mark!(shipped)
      stub_shopify(:orders_by_number, data: { orders: { nodes: [open_order] } })

      marker.auto_mark!('and what about #1001?')

      expect(conversation.reload.custom_attributes['shopify_order_number']).to eq('#1002')
    end

    it 'does nothing when the store hides customer data' do
      record.update!(customer_data_mode: 'limited')

      expect(marker.auto_mark!('order #1001')).to be_nil
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'the listener' do
    let(:listener) { Inclamo::OrderMarkListener.instance }

    def event_for(message)
      Events::Base.new('message.created', Time.zone.now, message: message)
    end

    it 'is one of the listeners of Chatwoot\'s dispatcher' do
      expect(AsyncDispatcher.new.listeners).to include(listener)
    end

    it 'starts a look for an order number on the first message of the customer only' do
      first = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'order #1001')

      expect { listener.message_created(event_for(first)) }.to have_enqueued_job(Inclamo::AutoMarkOrderJob).with(conversation.id, first.id)

      second = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'order #1002')
      reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'order #1003')
      expect { listener.message_created(event_for(second)) }.not_to have_enqueued_job(Inclamo::AutoMarkOrderJob)
      expect { listener.message_created(event_for(reply)) }.not_to have_enqueued_job(Inclamo::AutoMarkOrderJob)
    end

    it 'takes the first message as the first one also when the next one arrived before the job ran' do
      first = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'order #1001')
      second = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'and #1002')

      expect { listener.message_created(event_for(first)) }.to have_enqueued_job(Inclamo::AutoMarkOrderJob).with(conversation.id, first.id)
      expect { listener.message_created(event_for(second)) }.not_to have_enqueued_job(Inclamo::AutoMarkOrderJob)
    end

    it 'does nothing in an account without a working store connection' do
      record.update!(status: 'broken')
      first = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'order #1001')

      expect { listener.message_created(event_for(first)) }.not_to have_enqueued_job(Inclamo::AutoMarkOrderJob)
    end
  end

  describe 'attribute definitions' do
    it 'are created once per account, so macros and rules can pick them' do
      2.times { described_class.ensure_definitions!(account) }

      definitions = CustomAttributeDefinition.where(account: account, attribute_model: :conversation_attribute)
      expect(definitions.pluck(:attribute_key)).to match_array(described_class::DEFINITIONS.keys)
      expect(definitions.find_by(attribute_key: 'shopify_order_tracking_link').attribute_display_type).to eq('link')
    end
  end
end
