# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

# Store facts and the order a customer names are there before Chatwoot
# evaluates the automation rules of a new conversation. The rules themselves
# are Chatwoot's: these examples go through its listener, filter and actions.
RSpec.describe Inclamo::StoreFactsBeforeRules do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:team) { create(:team, account: account) }
  let(:listener) { AutomationRuleListener.instance }
  let(:maya) { shopify_fixture('customers_search_one').dig('customers', 'nodes', 0) }
  let(:open_order) { shopify_fixture('order_details_open')['order'] }
  let(:always) { [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }] }

  before do
    Inclamo::Shopify::OrderReader.forget!(account.id)
    Inclamo::Shopify::CustomerFacts.ensure_definitions!(account)
    Inclamo::Shopify::ConversationOrder.ensure_definitions!(account)
  end

  def fact(key, operator, value)
    [{ 'attribute_key' => key, 'filter_operator' => operator, 'values' => [value], 'query_operator' => nil, 'custom_attribute_type' => 'conversation_attribute' }]
  end

  def rule(event_name, conditions, *actions)
    create(:automation_rule, account: account, event_name: event_name, conditions: conditions,
                             actions: actions.map { |name, *params| { 'action_name' => name, 'action_params' => params } })
  end

  def from_customer(content)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def created!
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conversation))
  end

  def written!(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def spent_rule
    rule('conversation_created', fact('shopify_customer_spent', 'is_greater_than', '500'), ['change_priority', 'high'], ['assign_team', team.id])
  end

  describe 'the seam' do
    it 'stands in front of the two methods of Chatwoot\'s listener it wraps' do
      %i[conversation_created message_created].each do |name|
        ours = AutomationRuleListener.instance_method(name)
        expect(ours.owner).to eq(described_class)
        # Fails when Chatwoot renames the method: the upgrade routine runs this.
        expect(ours.super_method&.owner).to eq(AutomationRuleListener)
      end
    end
  end

  describe 'a new conversation of a customer' do
    before { stub_shopify_fixture(:customers_search, 'customers_search_one') }

    it 'fires a rule on the total spent' do
      spent_rule

      created!

      expect(conversation.reload).to have_attributes(priority: 'high', team: team)
      expect(conversation.custom_attributes).to include('shopify_customer_spent' => 5357.65, 'shopify_is_customer' => 'yes')
    end

    it 'keeps its priority and gets no team when the customer spent less' do
      spent_rule
      stub_shopify(:customers_search, data: { customers: { nodes: [maya.merge('amountSpent' => { 'amount' => '80.0', 'currencyCode' => 'UAH' })] } })

      created!

      expect(conversation.reload).to have_attributes(priority: nil, team: nil)
      expect(conversation.custom_attributes).to include('shopify_customer_spent' => 80)
    end

    it 'fires a rule on a tag of the customer' do
      rule('conversation_created', fact('shopify_customer_tags', 'contains', 'wholesale'), %w[add_label wholesale])
      stub_shopify(:customers_search, data: { customers: { nodes: [maya.merge('tags' => %w[b2b wholesale])] } })

      created!

      expect(conversation.reload.label_list).to eq(['wholesale'])
    end

    it 'fires a rule on the latest order' do
      rule('conversation_created', fact('shopify_last_order_fulfillment_status', 'equal_to', 'unfulfilled'), %w[add_label awaiting-shipment])

      created!

      expect(conversation.reload.label_list).to eq(['awaiting-shipment'])
    end

    it 'fires a rule of the customer\'s first message on the total spent' do
      rule('message_created', fact('shopify_customer_spent', 'is_greater_than', '500'), %w[add_label vip])

      written!(from_customer('Hello, I need help'))

      expect(conversation.reload.label_list).to eq(['vip'])
    end

    it 'ties the order the first message names before the rules look at the conversation' do
      rule('conversation_created', fact('shopify_order_number', 'equal_to', '#1001'), %w[add_label about-an-order])
      stub_shopify(:orders_by_number, data: { orders: { nodes: [open_order] } })
      from_customer('Hi, where is my order #1001?')

      created!

      expect(conversation.reload.label_list).to eq(['about-an-order'])
    end

    it 'asks the store nothing for a later message of the customer or a reply' do
      from_customer('Hello')
      later = from_customer('Are you there?')
      reply = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, content: 'Yes')

      written!(later)
      written!(reply)

      expect(WebMock).not_to have_requested(:any, /myshopify/)
      expect(conversation.reload.custom_attributes).to be_blank
    end
  end

  describe 'a new conversation of a contact the store does not know' do
    it 'fires a rule on "is a customer: no"' do
      rule('conversation_created', fact('shopify_is_customer', 'equal_to', 'no'), %w[add_label pre-sale])
      stub_shopify_fixture(:customers_search, 'customers_search_none')

      created!

      expect(conversation.reload.label_list).to eq(['pre-sale'])
    end
  end

  describe 'a store connected in the limited mode' do
    it 'gives the conversation no customer facts, and rules on them do not fire' do
      record.update!(customer_data_mode: 'limited')
      spent_rule
      rule('conversation_created', fact('shopify_is_customer', 'equal_to', 'no'), %w[add_label pre-sale])

      created!

      expect(conversation.reload).to have_attributes(priority: nil, team: nil, label_list: [], custom_attributes: {})
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'an account without a store' do
    it 'has its rules evaluated as before, and no store is asked' do
      record.destroy!
      rule('conversation_created', always, %w[add_label new])

      created!

      expect(conversation.reload.label_list).to eq(['new'])
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'a store that is silent' do
    before do
      spent_rule
      rule('conversation_created', always, %w[add_label new])
    end

    it 'does not hold the rules back: they run without the facts and the conversation is there' do
      stub_request(:post, shopify_graphql_url).to_timeout

      created!

      expect(conversation.reload).to have_attributes(priority: nil, team: nil, label_list: ['new'], custom_attributes: {})
    end

    it 'does the same when the store refuses the token' do
      stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{}')
      stub_token_refusal('app_not_installed')

      created!

      expect(conversation.reload).to have_attributes(priority: nil, label_list: ['new'], custom_attributes: {})
      expect(record.reload).to be_broken
    end

    it 'does the same for the rules of the first message' do
      rule('message_created', always, %w[add_label written])
      stub_request(:post, shopify_graphql_url).to_timeout

      written!(from_customer('Where is my order #1001?'))

      expect(conversation.reload.label_list).to eq(['written'])
    end

    it 'does the same when our own code fails, and reports the failure' do
      allow(Inclamo::Shopify::CustomerFacts).to receive(:new).and_raise(NoMethodError, 'a bug of ours')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      created!

      expect(conversation.reload.label_list).to eq(['new'])
      expect(tracker).to have_received(:capture_exception)
    end
  end

  describe 'the time limit' do
    def limits_of_store_calls
      limits = []
      allow(Inclamo::Shopify::Client).to receive(:new).and_wrap_original do |original, **arguments|
        limits << arguments[:time_limit]
        original.call(**arguments)
      end
      yield
      limits
    end

    it 'is five seconds for all the store calls of one event together' do
      contact.update!(phone_number: '+15005551011')
      by_email = stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body).dig('variables', 'query').to_s.start_with?('email:') }
                                                         .to_return(status: 200, body: { data: shopify_fixture('customers_search_none') }.to_json, headers: ShopifyStubs::JSON_HEADERS)
      stub_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body).dig('variables', 'query').to_s.start_with?('phone:') }
                                              .to_return(status: 200, body: { data: shopify_fixture('customers_search_phone') }.to_json, headers: ShopifyStubs::JSON_HEADERS)
      stub_shopify(:orders_by_number, data: { orders: { nodes: [open_order] } })
      from_customer('order #1001 please')

      limits = limits_of_store_calls { created! }

      expect(by_email).to have_been_requested.once
      expect(limits.size).to eq(3)
      expect(limits.first).to be_between(4.5, 5)
      expect(limits).to eq(limits.sort.reverse)
      expect(conversation.reload.custom_attributes).to include('shopify_is_customer' => 'yes', 'shopify_order_number' => '#1001')
    end

    it 'leaves nothing for a call made after it has run out' do
      reader = Inclamo::Shopify::BeforeRules::Reader.new(record, 0)

      expect { reader.customers_by_email('maya.example.t001@example.com') }.to raise_error(Inclamo::Shopify::Error::Timeout)
      expect(WebMock).not_to have_requested(:any, /myshopify/)
    end
  end

  describe 'the writes' do
    let(:dispatcher) { Rails.configuration.dispatcher }

    before do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      stub_shopify(:orders_by_number, data: { orders: { nodes: [open_order] } })
    end

    it 'publish no event, so they start no second evaluation of rules' do
      first = from_customer('Hi, where is my order #1001?')
      conversation.reload
      allow(dispatcher).to receive(:dispatch).and_call_original

      expect { Inclamo::Shopify::BeforeRules.call(conversation, message: first) }.not_to(change { conversation.reload.updated_at })

      expect(dispatcher).not_to have_received(:dispatch)
      expect(conversation.custom_attributes).to include('shopify_customer_orders' => 3, 'shopify_order_number' => '#1001')
    end

    it 'leave a rule for updated conversations unfired' do
      rule('conversation_updated', always, %w[add_label second-round])
      from_customer('Hi, where is my order #1001?')

      expect { created! }.not_to have_enqueued_job(EventDispatcherJob)

      expect(conversation.reload.label_list).to be_empty
    end

    it 'would publish one if they were not quiet' do
      conversation
      allow(dispatcher).to receive(:dispatch).and_call_original

      Inclamo::Shopify::CustomerFacts.new(conversation).refresh!

      expect(dispatcher).to have_received(:dispatch).with('conversation.updated', any_args)
    end
  end

  describe 'a rule that sends a message with an order variable' do
    before do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      stub_shopify(:orders_by_number, data: { orders: { nodes: [open_order] } })
      stub_shopify_fixture(:order_details, 'order_details_open')
    end

    it 'names the order of the first message to a new conversation' do
      rule('conversation_created', always, ['send_message', 'We are checking order {{order.number}}'])
      from_customer('Hi, where is my order #1001?')

      created!

      expect(conversation.messages.outgoing.last.content).to eq('We are checking order #1001')
    end

    it 'names it in a rule of the first message too' do
      rule('message_created', [{ 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['incoming'], 'query_operator' => nil }],
           ['send_message', 'We are checking order {{order.number}}'])

      written!(from_customer('Hi, where is my order #1001?'))

      expect(conversation.messages.outgoing.last.content).to eq('We are checking order #1001')
    end
  end
end
