# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopify_stubs')

RSpec.describe 'Inclamo preset rules API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/rule_presets" }
  let(:rules) { account.automation_rules.order(:id) }
  # Every account starts with the labels of the ready team queues; these are the others.
  let(:own_labels) { account.labels.where.not(title: Inclamo::TeamQueues.labels) }

  def presets
    response.parsed_body['presets'].index_by { |preset| preset['key'] }
  end

  def list(as: admin)
    get path, headers: as.create_new_auth_token, as: :json
  end

  def switch(key, active, value: nil, as: admin)
    put "#{path}/#{key}", params: { active: active, value: value }.compact, headers: as.create_new_auth_token, as: :json
  end

  describe 'the list' do
    it 'holds the three presets, all off in an account that never used them' do
      list

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('store_connected' => false, 'currency' => nil)
      expect(presets.keys).to eq(%w[vip not_shipped no_orders])
      expect(presets.values.pluck('name')).to eq(['VIP customers first', 'Order not shipped yet', 'No orders yet'])
      expect(presets.values).to all(include('on' => false, 'rule_id' => nil, 'value' => nil))
      expect(presets.transform_values { |preset| preset['needs_value'] }).to eq('vip' => true, 'not_shipped' => false, 'no_orders' => false)
    end

    it 'says whether a store is connected, and its currency' do
      create(:inclamo_shopify_connection, account: account)

      list

      expect(response.parsed_body).to include('store_connected' => true, 'currency' => 'EUR')
    end

    it 'is refused to an agent' do
      list(as: agent)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include('error' => 'forbidden')
      expect(response.parsed_body).not_to include('presets')
    end
  end

  describe 'switching on' do
    it 'creates an ordinary automation rule with the preset\'s name, and the label it adds' do
      switch('vip', true, value: '500')

      expect(response).to have_http_status(:success)
      rule = rules.sole
      expect(rule).to have_attributes(name: 'VIP customers first', event_name: 'conversation_created', active: true)
      expect(rule.conditions).to eq([{ 'attribute_key' => 'shopify_customer_spent', 'filter_operator' => 'is_greater_than', 'values' => ['500'],
                                       'query_operator' => nil, 'custom_attribute_type' => 'conversation_attribute' }])
      expect(rule.actions).to eq([{ 'action_name' => 'change_priority', 'action_params' => ['high'] }, { 'action_name' => 'add_label', 'action_params' => ['vip'] }])
      expect(rule.description.lines.last).to eq('inclamo-preset: vip')
      expect(own_labels.pluck(:title)).to eq(['vip'])
      expect(presets['vip']).to include('on' => true, 'rule_id' => rule.id, 'rule_name' => 'VIP customers first', 'value' => '500')
    end

    it 'shows the rule in Chatwoot\'s own automation list' do
      switch('vip', true, value: '500')

      get "/api/v1/accounts/#{account.id}/automation_rules", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('name', 'active')).to eq([['VIP customers first', true]])
    end

    it 'creates the two presets that need no value, with their labels' do
      switch('not_shipped', true)
      switch('no_orders', true)

      expect(rules.pluck(:name)).to eq(['Order not shipped yet', 'No orders yet'])
      expect(rules.first.conditions.pluck('attribute_key', 'filter_operator', 'values')).to eq([['shopify_last_order_fulfillment_status', 'equal_to', ['unfulfilled']]])
      expect(rules.last.conditions.pluck('attribute_key', 'filter_operator', 'values', 'query_operator'))
        .to eq([['shopify_is_customer', 'equal_to', ['no'], 'OR'], ['shopify_customer_orders', 'is_less_than', ['1'], nil]])
      expect(own_labels.pluck(:title)).to eq(%w[awaiting-shipment pre-sale])
    end

    it 'creates one rule however often it is asked, and keeps a label that was there' do
      create(:label, account: account, title: 'vip', color: '#ff0000')

      2.times { switch('vip', true, value: '500') }

      expect(rules.count).to eq(1)
      expect(own_labels.sole.color).to eq('#ff0000')
    end

    it 'needs an amount for the VIP preset: zero or more' do
      [nil, '', 'a lot', '-5'].each do |value|
        switch('vip', true, value: value)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'value_required')
      end
      expect(rules.count).to eq(0)
    end

    it 'keeps the amount as it was entered: whole or with a fraction' do
      switch('vip', true, value: ' 499.50 ')
      expect(presets['vip']['value']).to eq('499.5')

      switch('vip', true, value: '1000.00')
      expect(presets['vip']['value']).to eq('1000')
    end

    it 'is refused to an agent' do
      switch('vip', true, value: '500', as: agent)

      expect(response).to have_http_status(:forbidden)
      expect(rules.count).to eq(0)
      expect(own_labels.count).to eq(0)
    end

    it 'knows nothing of a preset that does not exist' do
      switch('everything', true)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'switching off' do
    before { switch('vip', true, value: '500') }

    it 'deactivates the rule and deletes nothing' do
      switch('vip', false)

      expect(rules.sole).to have_attributes(active: false, name: 'VIP customers first')
      expect(presets['vip']).to include('on' => false, 'rule_id' => rules.sole.id, 'value' => '500')
    end

    it 'keeps what the administrator changed in the rule, also when it is switched on again' do
      rule = rules.sole
      edited = [rule.conditions.first.merge('query_operator' => 'AND'),
                { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
      rule.update!(name: 'Our best customers', conditions: edited, actions: rule.actions + [{ 'action_name' => 'add_label', 'action_params' => ['gold'] }])

      switch('vip', false)
      expect(rule.reload).to have_attributes(active: false, name: 'Our best customers', conditions: edited)

      switch('vip', true, value: '800')
      expect(rules.count).to eq(1)
      expect(rule.reload).to have_attributes(active: true, name: 'Our best customers')
      expect(rule.conditions.pluck('attribute_key', 'values')).to eq([['shopify_customer_spent', ['800']], ['status', ['open']]])
      expect(rule.actions.last).to eq('action_name' => 'add_label', 'action_params' => ['gold'])
      expect(presets['vip']).to include('on' => true, 'rule_name' => 'Our best customers', 'value' => '800')
    end

    it 'is refused to an agent' do
      switch('vip', false, as: agent)

      expect(response).to have_http_status(:forbidden)
      expect(rules.sole).to be_active
    end

    it 'does nothing for a preset that was never switched on' do
      switch('no_orders', false)

      expect(response).to have_http_status(:success)
      expect(rules.count).to eq(1)
    end

    it 'no longer knows a rule whose marker line was removed: the preset is off and switching it on makes a new rule' do
      rules.sole.update!(description: 'Ours now.')

      list
      expect(presets['vip']).to include('on' => false, 'rule_id' => nil)

      switch('vip', true, value: '500')
      expect(rules.count).to eq(2)
    end
  end

  # The rules are Chatwoot's: these go through its listener, with the store facts written first.
  describe 'the rules at work' do
    let(:record) { create(:inclamo_shopify_connection, account: account) }
    let(:contact) { create(:contact, account: account, email: 'maya.example.t001@example.com') }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:maya) { shopify_fixture('customers_search_one').dig('customers', 'nodes', 0) }

    before do
      Inclamo::Shopify::OrderReader.forget!(record.account_id)
      %w[not_shipped no_orders].each { |key| switch(key, true) }
      switch('vip', true, value: '5357.65')
    end

    def created!(customers)
      stub_shopify(:customers_search, data: { customers: { nodes: customers } })
      AutomationRuleListener.instance.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conversation))
      conversation.reload
    end

    it 'puts a customer who spent more than the amount first' do
      created!([maya.merge('amountSpent' => { 'amount' => '5357.66', 'currencyCode' => 'UAH' })])

      expect(conversation).to have_attributes(priority: 'high', label_list: match_array(%w[vip awaiting-shipment]))
    end

    it 'does not count a customer who spent exactly the amount' do
      created!([maya])

      expect(conversation).to have_attributes(priority: nil, label_list: ['awaiting-shipment'])
    end

    it 'marks someone the store does not know as pre-sale' do
      created!([])

      expect(conversation).to have_attributes(priority: nil, label_list: ['pre-sale'])
    end

    it 'marks a customer of the store who has not ordered yet as pre-sale too' do
      created!([maya.merge('numberOfOrders' => '0', 'amountSpent' => { 'amount' => '0.0', 'currencyCode' => 'UAH' }, 'latestOrders' => { 'nodes' => [] })])

      expect(conversation.label_list).to eq(['pre-sale'])
    end

    it 'leaves the conversation alone once the presets are switched off' do
      %w[vip not_shipped no_orders].each { |key| switch(key, false) }

      created!([maya.merge('amountSpent' => { 'amount' => '9000.0', 'currencyCode' => 'UAH' })])

      expect(conversation).to have_attributes(priority: nil, label_list: [])
    end
  end
end
