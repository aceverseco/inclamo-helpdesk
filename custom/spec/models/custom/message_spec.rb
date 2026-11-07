# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

# Order variables in outgoing messages: `{{order.*}}` is rendered when the
# message is created, for an agent's reply and a macro's message alike.
RSpec.describe Custom::Message do
  let(:record) { create(:inclamo_shopify_connection) }
  let(:account) { record.account }
  # Maya, the customer of the recorded answers, with three orders; #1003 is the newest.
  let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:shipped) { shopify_fixture('order_details_shipped')['order'] }
  let(:every_variable) { Inclamo::Shopify::OrderVariables::NAMES.map { |name| "#{name}=[{{order.#{name}}}]" }.join(' ') }

  before { Inclamo::Shopify::OrderReader.forget!(account.id) }

  def tie!(node)
    Inclamo::Shopify::ConversationOrder.new(conversation).mark!(node)
  end

  def send_reply(content)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation.reload, message_type: :outgoing, content: content).content
  end

  describe 'a conversation tied to an order' do
    before { tie!(shipped) }

    it 'renders every order variable from the store' do
      stub_shopify_fixture(:order_details, 'order_details_shipped')

      text = send_reply(every_variable)

      expect(text).to include(
        'number=[#1002]', 'date=[November 5, 2026]', 'total=[1,585.90 UAH]', 'payment_status=[Paid]', 'fulfillment_status=[Shipped]',
        'tracking_number=[E2Et001A]', 'tracking_link=[https://example.com/track/E2Et001A]', "status_link=[#{shipped['statusPageUrl']}]",
        "items=[1 × The Minimal Snowboard\n1 × The Complete Snowboard]"
      )
      expect(text).not_to include('{{')
    end

    it 'reads the order at the moment of sending, not what the conversation last knew' do
      fresher = shipped.deep_dup
      fresher['fulfillments'].first['trackingInfo'].first.merge!('number' => 'NEW123', 'url' => 'https://example.com/track/NEW123')
      stub_shopify(:order_details, data: { order: fresher })

      expect(send_reply('{{order.tracking_number}} {{order.tracking_link}}')).to eq('NEW123 https://example.com/track/NEW123')
      expect(conversation.reload.custom_attributes['shopify_order_tracking_number']).to eq('E2Et001A')
    end

    it 'renders them in the message a macro sends' do
      stub_shopify_fixture(:order_details, 'order_details_shipped')
      agent = create(:user, account: account)
      create(:inbox_member, user: agent, inbox: conversation.inbox)
      macro = create(:macro, account: account, actions: [{ action_name: 'send_message', action_params: ['Order {{order.number}} is {{order.fulfillment_status}}.'] }])

      Macros::ExecutionService.new(macro, conversation, agent).perform

      expect(conversation.messages.outgoing.last.content).to eq('Order #1002 is Shipped.')
    end

    it 'is the tied order, not the newest order of the customer' do
      stub_shopify_fixture(:order_details, 'order_details_shipped')
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      stub_shopify_fixture(:customer_orders, 'customer_orders')

      expect(send_reply('{{order.number}}')).to eq('#1002')
      expect(a_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].match?(/^query customer/) }).not_to have_been_made
    end

    it 'gives the store three seconds' do
      stub_shopify_fixture(:order_details, 'order_details_shipped')
      limits = []
      allow(Inclamo::Shopify::Client).to receive(:new).and_wrap_original do |original, **arguments|
        limits << arguments[:time_limit]
        original.call(**arguments)
      end

      send_reply('{{order.number}}')

      expect(limits.size).to eq(1)
      expect(limits.first).to be_between(2.5, 3)
    end

    it 'sends the message with the last known values when the store does not answer in time' do
      stub_request(:post, shopify_graphql_url).to_timeout

      text = send_reply(every_variable)

      expect(text).to include('number=[#1002]', 'payment_status=[Paid]', 'fulfillment_status=[Shipped]', 'tracking_number=[E2Et001A]',
                              'tracking_link=[https://example.com/track/E2Et001A]')
      expect(text).to include('date=[]', 'total=[]', 'status_link=[]', 'items=[]')
    end

    it 'sends the message with the last known values when the store refuses the token' do
      stub_request(:post, shopify_graphql_url).to_return(status: 401, body: '{"errors":"[API] Invalid API key or access token"}')
      stub_token_refusal('invalid_client')

      expect(send_reply('{{order.number}} {{order.fulfillment_status}} total: {{order.total}}')).to eq('#1002 Shipped total: ')
      expect(record.reload).to be_broken

      # Broken from now on: the store is not called, the last known values still serve.
      WebMock.reset!
      expect(send_reply('{{order.number}}')).to eq('#1002')
    end

    it 'makes no store call for a message without order variables' do
      expect(send_reply('Hello {{contact.name}}, thank you for writing.')).to start_with('Hello ')
      expect(a_request(:post, shopify_graphql_url)).not_to have_been_made
    end

    it 'reads the order once for a message with several variables' do
      request = stub_shopify_fixture(:order_details, 'order_details_shipped')
      Inclamo::Shopify::OrderReader.forget!(account.id)

      send_reply(every_variable)

      expect(request).to have_been_requested.once
    end

    it 'leaves an incoming message as it is written' do
      incoming = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, content: 'I saw {{order.number}}')

      expect(incoming.content).to eq('I saw {{order.number}}')
      expect(a_request(:post, shopify_graphql_url)).not_to have_been_made
    end
  end

  describe 'a conversation without a tied order' do
    before { stub_shopify_fixture(:customer_orders, 'customer_orders') }

    it 'renders the newest order of the customer the contact is matched to' do
      stub_shopify_fixture(:customers_search, 'customers_search_one')

      expect(send_reply('{{order.number}}: {{order.payment_status}}, {{order.items}}')).to eq("#1003: Partially refunded, 2 × The Complete Snowboard")
    end

    it 'renders it in the message a macro sends' do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      agent = create(:user, account: account)
      create(:inbox_member, user: agent, inbox: conversation.inbox)
      macro = create(:macro, account: account, actions: [{ action_name: 'send_message', action_params: ['About order {{order.number}}: thank you.'] }])

      Macros::ExecutionService.new(macro, conversation, agent).perform

      expect(conversation.messages.outgoing.last.content).to eq('About order #1003: thank you.')
    end

    it 'takes the customer an agent chose for the contact' do
      Inclamo::Shopify::CustomerMatcher.remember!(contact, shopify_fixture('customers_search_one').dig('customers', 'nodes', 0, 'id'))

      expect(send_reply('{{order.number}}')).to eq('#1003')
      expect(a_request(:post, shopify_graphql_url).with { |r| JSON.parse(r.body)['query'].match?(/^query customers_search/) }).not_to have_been_made
    end

    it 'renders the order variables as empty text when the contact matches no customer' do
      stub_shopify_fixture(:customers_search, 'customers_search_none')

      expect(send_reply(every_variable)).to eq(Inclamo::Shopify::OrderVariables::NAMES.map { |name| "#{name}=[]" }.join(' '))
    end

    it 'renders them as empty text when the customer has no orders, and in a macro too' do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      without_orders = shopify_fixture('customer_orders')
      without_orders['customer']['orders']['nodes'] = []
      stub_shopify(:customer_orders, data: without_orders)
      agent = create(:user, account: account)
      create(:inbox_member, user: agent, inbox: conversation.inbox)
      macro = create(:macro, account: account, actions: [{ action_name: 'send_message', action_params: ['About order {{order.number}}: thank you.'] }])

      Macros::ExecutionService.new(macro, conversation, agent).perform

      expect(conversation.messages.outgoing.last.content).to eq('About order : thank you.')
    end

    it 'renders them as empty text when the store hides its customers' do
      record.update!(customer_data_mode: 'limited')

      expect(send_reply('[{{order.number}}]')).to eq('[]')
      expect(a_request(:post, shopify_graphql_url)).not_to have_been_made
    end

    it 'renders them as empty text, with no last known values, when the store does not answer' do
      WebMock.reset!
      stub_request(:post, shopify_graphql_url).to_timeout

      expect(send_reply(every_variable)).to eq(Inclamo::Shopify::OrderVariables::NAMES.map { |name| "#{name}=[]" }.join(' '))
    end

    it 'gives the store three seconds in all for the customer and the orders' do
      stub_shopify_fixture(:customers_search, 'customers_search_one')
      limits = []
      allow(Inclamo::Shopify::Client).to receive(:new).and_wrap_original do |original, **arguments|
        limits << arguments[:time_limit]
        original.call(**arguments)
      end

      send_reply('{{order.number}}')

      expect(limits.size).to eq(2)
      expect(limits.first).to be_between(2.5, 3)
      expect(limits.last).to be < limits.first
    end

    it 'makes no store call for a message without order variables' do
      send_reply('Hello {{contact.name}}.')

      expect(a_request(:post, shopify_graphql_url)).not_to have_been_made
    end
  end

  it 'renders the order variables as empty text in an account with no store connection' do
    other = create(:conversation, custom_attributes: { 'shopify_order_id' => shipped['id'], 'shopify_order_number' => '#1002' })

    message = create(:message, account: other.account, inbox: other.inbox, conversation: other, message_type: :outgoing, content: 'Order [{{order.number}}]')

    expect(message.content).to eq('Order []')
  end
end
