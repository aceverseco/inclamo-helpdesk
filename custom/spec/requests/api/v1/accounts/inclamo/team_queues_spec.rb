# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inclamo team queues API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:closed_inbox) { create(:inbox, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/team_queues" }
  let(:records) { Inclamo::TeamQueue.where(account_id: account.id).ordered }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def list(as: admin, **params)
    get path, params: params, headers: as.create_new_auth_token
  end

  def queues
    response.parsed_body['queues'].index_by { |queue| queue['key'] }
  end

  def change(key, as: admin, **params)
    patch "#{path}/#{records.find_by(key: key).id}", params: params, headers: as.create_new_auth_token, as: :json
  end

  def error
    response.parsed_body['error']
  end

  describe 'the list' do
    it 'gives every staff member the same queues, with the native filter payload' do
      [admin, agent].each do |user|
        list(as: user)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['limit']).to eq(20)
        expect(queues.keys).to eq(%w[urgent ai_handover overdue delivery cancellation damage missing_parts return])
        expect(queues['urgent']).to include('name' => 'Urgent', 'position' => 1, 'hidden' => false, 'ready' => true, 'count' => 0)
        expect(queues['return']['query']).to eq(
          'payload' => [
            { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'attribute_model' => 'standard',
              'custom_attribute_type' => '', 'query_operator' => 'and' },
            { 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => %w[return inclamo_intent_return], 'attribute_model' => 'standard',
              'custom_attribute_type' => '' }
          ]
        )
      end
    end

    it "counts what the staff member may see: an agent outside an inbox gets less than an administrator" do
      create(:conversation, account: account, inbox: inbox, priority: :urgent)
      create(:conversation, account: account, inbox: closed_inbox, priority: :urgent)
      create(:conversation, account: account, inbox: inbox, priority: :urgent, status: :resolved)
      create(:conversation, account: account, inbox: inbox, priority: :urgent, status: :snoozed)
      create(:conversation, account: account, inbox: inbox).update_labels(['return'])
      create(:conversation, account: account, inbox: inbox).update_labels(['inclamo_intent_return'])
      create(:conversation, account: account, inbox: inbox).update_labels(%w[inclamo_handover inclamo_urgent])
      create(:conversation, account: account, inbox: inbox).update_labels(['inclamo_limit'])
      create(:conversation, account: account, inbox: inbox, status: :resolved).update_labels(['inclamo_error'])

      list(as: admin)
      expect(queues.transform_values { |queue| queue['count'] }).to include('urgent' => 2, 'return' => 2, 'ai_handover' => 2, 'overdue' => 0)

      list(as: agent)
      expect(queues['urgent']['count']).to eq(1)
    end

    it "the count is the size of the list Chatwoot's filter gives with the same payload" do
      3.times { create(:conversation, account: account, inbox: inbox, priority: :urgent) }
      list(as: agent)
      urgent = queues['urgent']

      post "/api/v1/accounts/#{account.id}/conversations/filter", params: { payload: urgent['query']['payload'] },
                                                                 headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['meta']['all_count']).to eq(3)
      expect(urgent['count']).to eq(3)
    end

    it 'leaves hidden queues out, except for an administrator who asks for all' do
      records.find_by(key: 'cancellation').update!(hidden: true)

      list(as: agent, all: 1)
      expect(queues.keys).not_to include('cancellation')
      list(as: admin)
      expect(queues.keys).not_to include('cancellation')
      list(as: admin, all: 1)
      expect(queues['cancellation']).to include('hidden' => true, 'count' => nil)
    end
  end

  describe 'managing' do
    it 'renames a queue for everyone, with the same membership' do
      change('missing_parts', name: ' Parts requests ')

      expect(response).to have_http_status(:success)
      list(as: agent)
      expect(queues['missing_parts']).to include('name' => 'Parts requests')
      expect(queues['missing_parts']['query']).to eq(Inclamo::TeamQueues.shipped_query('missing_parts'))
    end

    it 'refuses a blank name' do
      change('urgent', name: ' ')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error).to eq('name_invalid')
      expect(records.find_by(key: 'urgent').name).to eq('Urgent')
    end

    it 'hides a queue and shows it again at its place' do
      change('cancellation', hidden: true)
      list(as: agent)
      expect(queues.keys).not_to include('cancellation')

      change('cancellation', hidden: false)
      list(as: agent)
      expect(queues.keys.index('cancellation')).to eq(4)
    end

    it 'refuses to show a twenty-first queue' do
      12.times { |index| Inclamo::TeamQueue.create!(account: account, name: "Own #{index}", position: 20 + index, query: Inclamo::TeamQueues.shipped_query('urgent')) }
      records.find_by(key: 'urgent').update_column(:hidden, true) # rubocop:disable Rails/SkipsModelValidations
      Inclamo::TeamQueue.create!(account: account, name: 'Own 12', position: 40, query: Inclamo::TeamQueues.shipped_query('urgent'))

      change('urgent', hidden: false)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error).to eq('too_many_visible')
      expect(records.find_by(key: 'urgent').hidden).to be(true)
    end

    it 'reorders the queues for everyone' do
      ids = records.pluck(:id)
      first = records.find_by(key: 'return').id

      post "#{path}/reorder", params: { ids: [first] + (ids - [first]) }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      list(as: agent)
      expect(queues.keys.first).to eq('return')
    end

    it 'refuses an order that does not name every queue once' do
      post "#{path}/reorder", params: { ids: records.pluck(:id).first(3) }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error).to eq('order_incomplete')
    end

    it 'restores the shipped name, place and query, and leaves the queue hidden if it was' do
      queue = records.find_by(key: 'missing_parts')
      queue.update!(name: 'Parts requests', position: 1, hidden: true, query: Inclamo::TeamQueues.shipped_query('urgent'))

      post "#{path}/#{queue.id}/restore", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(queue.reload).to have_attributes(name: 'Missing parts', position: 7, hidden: true, query: Inclamo::TeamQueues.shipped_query('missing_parts'))
    end

    it "does not reach another account's queue" do
      other = Inclamo::TeamQueue.find_by(account_id: create(:account).id, key: 'urgent')

      patch "#{path}/#{other.id}", params: { name: 'Taken' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other.reload.name).to eq('Urgent')
    end

    it 'is closed to agents' do
      queue = records.find_by(key: 'urgent')
      headers = agent.create_new_auth_token

      patch "#{path}/#{queue.id}", params: { name: 'Mine now', hidden: true }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{path}/reorder", params: { ids: records.pluck(:id).reverse }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{path}/#{queue.id}/restore", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      expect(queue.reload).to have_attributes(name: 'Urgent', hidden: false, position: 1)
    end
  end

  describe 'a ready reply' do
    it 'is listed with the saved replies of the account' do
      get "/api/v1/accounts/#{account.id}/canned_responses", headers: admin.create_new_auth_token

      expect(response.parsed_body.pluck('short_code')).to include('delivery-status', 'cancel-confirm', 'damage-photos', 'missing-part', 'return-start')
    end
  end
end
