# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')

# The ticket of a request about one shopper as its card reads it, and the
# card's actions: "Delete", "Hold", "Lift hold", "Mark answered"
# (docs/app-store-erasure.md §4.2, §5). Administrators only.
RSpec.describe 'Inclamo shopper requests API', type: :request do
  include_context 'with app provisioning'
  include ShopperRequests

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }
  let(:admin) { store_administrator }
  let(:agent) { create(:user, account: account, role: :agent) }
  before { active_store }

  let!(:shopper) { shopper_contact(account) }

  around { |example| travel_to(now) { example.run } }


  def erasure
    ask_shopper_erasure(order_ids: ['299938'])
    shopper_request
  end

  def data_request
    ask_data_request
    shopper_request('shopper_data_request')
  end

  def act(request, action, user = admin, **params)
    post shopper_path(account, request, action), params: params, headers: user.create_new_auth_token, as: :json
    response
  end

  def card(request, user = admin)
    get shopper_path(account, request), headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  describe 'who may act' do
    it 'refuses an agent every address, and changes nothing' do
      request = erasure
      asked = data_request
      create(:inbox_member, user: agent, inbox: shopper.conversations.first.inbox)

      get shopper_path(account, request), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('pat@example.com')
      [[request, 'delete'], [request, 'hold'], [request, 'lift'], [asked, 'answered']].each do |one, action|
        expect(act(one, action, agent, reason: 'because')).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq('forbidden')
      end

      expect(request.reload.state).to eq('waiting')
      expect(asked.reload.state).to eq('waiting')
      expect(Contact.exists?(shopper.id)).to be(true)
    end

    it 'answers not found for a request of another account' do
      request = erasure
      other = create(:account)
      create(:account_user, account: other, user: admin, role: :administrator)

      get "/api/v1/accounts/#{other.id}/inclamo/shopper_requests/#{request.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the card' do
    it 'shows a waiting erasure with the shopper\'s email and phone, the contacts found now and the date' do
      request = erasure

      expect(card(request)).to eq(
        'id' => request.id, 'kind' => 'shopper_erasure', 'state' => 'waiting', 'conversation_id' => request.conversation_id,
        'received_at' => '2026-11-20T10:00:00Z', 'delete_after' => '2026-12-04T10:00:00Z', 'overdue' => false,
        'email' => 'pat@example.com', 'phone' => '+15556251199',
        'contacts' => [{ 'id' => shopper.id, 'name' => shopper.name, 'conversations' => 2 }], 'hold' => nil, 'done' => nil
      )
    end
  end

  describe 'Hold and Lift hold' do
    it 'holds with a reason, shows who, when and why, writes a note and resolves the ticket' do
      request = erasure

      expect(act(request, 'hold', reason: '  open payment dispute ')).to have_http_status(:ok)

      expect(response.parsed_body).to include('state' => 'held', 'delete_after' => '2026-12-04T10:00:00Z',
                                              'hold' => { 'reason' => 'open payment dispute', 'held_at' => '2026-11-20T10:00:00Z',
                                                          'held_by' => { 'id' => admin.id, 'name' => admin.available_name } })
      ticket = ticket_of(request)
      expect(ticket.status).to eq('resolved')
      note = ticket.messages.reorder(:id).last
      expect(note).to have_attributes(private: true, sender: admin)
      expect(note.content).to include('held the automatic deletion', 'the store answers for this request')
      expect(note.content).not_to include('payment dispute')
      expect(events_of.last).to eq('shopper_held')
    end

    it 'refuses a hold without a reason, and the date is unchanged' do
      request = erasure

      ['', '   ', nil].each do |reason|
        expect(act(request, 'hold', reason: reason)).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'reason_missing')
      end

      expect(request.reload).to have_attributes(state: 'waiting', delete_after: now + 14.days, hold_reason: nil, held_at: nil)
      expect(ticket_of(request).messages.count).to eq(1)
    end

    it 'lifts the hold before the date: the date is kept and the ticket opened again' do
      request = erasure
      act(request, 'hold', reason: 'open payment dispute')
      travel 3.days

      expect(act(request, 'lift')).to have_http_status(:ok)

      expect(response.parsed_body).to include('state' => 'waiting', 'delete_after' => '2026-12-04T10:00:00Z', 'hold' => nil)
      expect(request.reload).to have_attributes(hold_reason: nil, held_by_id: nil, held_at: nil)
      ticket = ticket_of(request)
      expect(ticket.status).to eq('open')
      expect(ticket.messages.reorder(:id).last.content).to include('lifted the hold', '2026-12-04 10:00 UTC')
      expect(events_of.last).to eq('shopper_hold_lifted')
    end

    it 'lifts the hold after the date: the note says the next daily run deletes' do
      request = erasure
      act(request, 'hold', reason: 'open payment dispute')
      travel 20.days

      act(request, 'lift')

      expect(ticket_of(request).messages.reorder(:id).last.content).to include('has passed', 'next daily run')
    end
  end

  describe 'Delete' do
    it 'deletes the shopper\'s data and finishes the ticket, naming the administrator' do
      request = erasure
      travel 2.days

      perform_enqueued_jobs { expect(act(request, 'delete')).to have_http_status(:ok) }

      expect(response.parsed_body).to include(
        'state' => 'done', 'email' => nil, 'phone' => nil, 'contacts' => [],
        'done' => { 'at' => '2026-11-22T10:00:00Z', 'by' => 'team', 'user' => { 'id' => admin.id, 'name' => admin.available_name } }
      )
      expect(Contact.exists?(shopper.id)).to be(false)
      expect(Conversation.where(contact_id: shopper.id)).to be_empty
      expect(ticket_of(request).messages.reorder(:id).last.content).to eq("Done: #{admin.available_name} deleted the shopper's data on 2026-11-22 10:00 UTC.")
      expect(events_of.last).to eq('shopper_deleted')
    end

    it 'deletes a held request too' do
      request = erasure
      act(request, 'hold', reason: 'open payment dispute')

      perform_enqueued_jobs { act(request, 'delete') }

      expect(response.parsed_body).to include('state' => 'done', 'hold' => nil)
      expect(request.reload.hold_reason).to be_nil
      expect(Contact.exists?(shopper.id)).to be(false)
    end

    it 'keeps everything when the journal cannot be written, and says it was not done' do
      request = erasure
      allow(Rails.logger).to receive(:error)

      with_modified_env(INCLAMO_ERASURE_JOURNAL_PATH: '/nonexistent-dir/erasures.jsonl') { act(request, 'delete') }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'not_done')
      expect(request.reload).to have_attributes(state: 'waiting', email: 'pat@example.com')
      expect(Contact.exists?(shopper.id)).to be(true)
      expect(Rails.logger).to have_received(:error).with(/ALERT the erasure journal cannot be written/)
    end
  end

  describe 'Mark answered' do
    it 'finishes a data request: no email or phone any longer, the ticket closed, nothing deleted' do
      request = data_request

      expect(act(request, 'answered')).to have_http_status(:ok)

      expect(response.parsed_body).to include('state' => 'done', 'email' => nil, 'phone' => nil, 'contacts' => [],
                                              'done' => include('by' => 'team', 'user' => include('id' => admin.id)))
      expect(request.reload).to have_attributes(email: nil, phone: nil, done_by: 'team', done_by_id: admin.id)
      expect(ticket_of(request).status).to eq('resolved')
      expect(ticket_of(request).messages.reorder(:id).last.content).to include('marked the request answered')
      expect(Contact.exists?(shopper.id)).to be(true)
      expect(events_of.last).to eq('data_request_answered')
    end
  end

  describe 'an action in a state it does not belong to' do
    it 'is refused, and changes nothing' do
      request = erasure
      asked = data_request

      [[request, 'lift'], [request, 'answered'], [asked, 'delete'], [asked, 'hold'], [asked, 'lift']].each do |one, action|
        expect(act(one, action, reason: 'because')).to have_http_status(:conflict)
        expect(response.parsed_body).to eq('error' => 'wrong_state', 'state' => 'waiting')
      end
      act(request, 'hold', reason: 'open payment dispute')
      expect(act(request, 'hold', reason: 'again')).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'wrong_state', 'state' => 'held')
      perform_enqueued_jobs { act(request, 'delete') }
      act(asked, 'answered')
      [[request, 'delete'], [request, 'hold'], [request, 'lift'], [asked, 'answered']].each do |one, action|
        expect(act(one, action, reason: 'because')).to have_http_status(:conflict)
        expect(response.parsed_body).to eq('error' => 'wrong_state', 'state' => 'done')
      end
      expect(request.reload.done_by_id).to eq(admin.id)
    end
  end
end
