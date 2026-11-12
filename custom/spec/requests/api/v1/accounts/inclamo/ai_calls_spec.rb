# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/ai_service_stubs')

RSpec.describe 'Inclamo AI agent: filing a finished call', type: :request do
  include AiServiceStubs

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:website) { create(:channel_widget, account: account).inbox }
  let!(:record) { connect_ai_agent(account, [website]) }
  let(:bot) { AgentBot.find(record.agent_bot_id) }
  let(:phone_inbox) { Inbox.find(record.phone_inbox_id) }
  let(:bot_headers) { { 'api_access_token' => bot.access_token.token } }
  let(:path) { "/api/v1/accounts/#{account.id}/inclamo/calls" }

  let(:turns) do
    [
      { role: 'agent', text: "Hello, you have reached the shop's assistant.", at: '2026-11-07T14:00:01Z' },
      { role: 'caller', text: 'Hi, a part is missing from my order.', at: '2026-11-07T14:00:06Z' },
      { role: 'agent', text: 'Which order is it?', at: '2026-11-07T14:00:11Z' },
      { role: 'caller', text: 'Order 1042.', at: '2026-11-07T14:00:15Z' }
    ]
  end

  # As a connection leaves the account: with the AI service's fixed labels.
  before { Inclamo::Ai::Labels.ensure_fixed!(account) }

  def call(overrides = {})
    {
      call_id: 'c-17', entry: 'inbound', line: '+15550100100',
      caller: { phone: '+15550100001', name: 'Anna' },
      ended_at: '2026-11-07T14:03:12Z', duration: 192, outcome: 'request', needs_team: true,
      labels: %w[inclamo_call inclamo_inbound inclamo_handover inclamo_escalation],
      turns: turns, record: "Request for the team · Inbound call · +1 555 010 0001\n\nSummary: a part is missing."
    }.merge(overrides)
  end

  def file(headers: bot_headers, **overrides)
    post path, params: call(overrides), headers: headers, as: :json
  end

  def body
    response.parsed_body
  end

  def filed
    account.conversations.find_by!(display_id: body['conversation_id'])
  end

  def nothing_filed
    expect(account.conversations.count).to eq(0)
    expect(Inclamo::CallConversation.count).to eq(0)
    expect(Message.count).to eq(0)
  end

  describe 'who may file' do
    it 'files a call for the connection\'s agent bot' do
      file

      expect(response).to have_http_status(:created)
      expect(filed.inbox_id).to eq(phone_inbox.id)
    end

    it 'refuses a request without a token' do
      file(headers: {})

      expect(response).to have_http_status(:unauthorized)
      nothing_filed
    end

    it 'refuses the token of an administrator' do
      file(headers: { 'api_access_token' => admin.access_token.token })

      expect(response).to have_http_status(:unauthorized)
      expect(body['error']).to eq('unauthorized')
      nothing_filed
    end

    it 'refuses a dashboard session' do
      file(headers: admin.create_new_auth_token)

      expect(response).to have_http_status(:unauthorized)
      nothing_filed
    end

    it 'refuses another agent bot of the account' do
      other = create(:agent_bot, account: account)

      file(headers: { 'api_access_token' => other.access_token.token })

      expect(response).to have_http_status(:unauthorized)
      nothing_filed
    end

    it 'refuses a bot of an account where the AI agent is not connected, with not_connected' do
      record.update!(state: 'disconnected')

      file

      expect(response).to have_http_status(:conflict)
      expect(body).to include('error' => 'not_connected', 'code' => 'not_connected')
      nothing_filed
    end

    it 'refuses the token of the bot removed by a disconnection' do
      token = bot.access_token.token
      stub_ai_removal
      resolve_ai_service_publicly
      Inclamo::Ai::Disconnect.call(account: account)

      file(headers: { 'api_access_token' => token })

      expect(response).to have_http_status(:unauthorized)
      nothing_filed
    end

    it 'answers not_connected when the Phone inbox is gone' do
      record.update!(phone_inbox_id: nil)

      file

      expect(response).to have_http_status(:conflict)
      expect(body['code']).to eq('not_connected')
    end
  end

  describe 'the conversation of a call' do
    it 'holds the turns as messages in the call\'s order, the record as the last private note, and the call\'s attributes' do
      file(recording_url: 'https://ai.example.com/calls/c-17')

      expect(response).to have_http_status(:created)
      expect(body).to include('found' => false, 'matched_by' => 'created', 'labels_added' => [])
      conversation = filed
      expect(conversation.status).to eq('open')
      expect(conversation.custom_attributes).to eq(
        'inclamo_call_entry' => 'inbound', 'inclamo_call_line' => '+15550100100', 'inclamo_call_caller' => '+15550100001',
        'inclamo_call_duration' => 192, 'inclamo_call_ended_at' => '2026-11-07T14:03:12Z', 'inclamo_call_outcome' => 'request',
        'inclamo_call_matched_by' => 'created', 'inclamo_call_recording' => 'https://ai.example.com/calls/c-17'
      )

      # Read back through Chatwoot's own messages endpoint.
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: admin.create_new_auth_token, as: :json
      messages = response.parsed_body['payload']
      expect(messages.pluck('content')).to eq(turns.pluck(:text) + [call[:record]])
      expect(messages.pluck('message_type')).to eq([1, 0, 1, 0, 1])
      expect(messages.pluck('private')).to eq([false, false, false, false, true])
      expect(messages.first(4).pluck('created_at')).to eq(turns.map { |turn| Time.iso8601(turn[:at]).to_i })
      expect(messages[0]['sender']).to include('id' => bot.id, 'type' => 'agent_bot')
      expect(messages[1]['sender']).to include('id' => conversation.contact_id, 'type' => 'contact')
      expect(messages[4]['sender']).to include('id' => bot.id, 'type' => 'agent_bot')
      expect(messages.pluck('status').uniq).to eq(['sent'])
    end

    it 'keeps a call where the caller said nothing as the record alone' do
      file(turns: [], outcome: 'no_conversation', needs_team: false, record: 'No conversation · Inbound call')

      expect(response).to have_http_status(:created)
      expect(filed.messages.pluck(:content, :private)).to eq([['No conversation · Inbound call', true]])
      expect(filed.status).to eq('resolved')
    end

    it 'puts turns without times one second apart, ending at the call\'s end' do
      file(turns: turns.map { |turn| turn.except(:at) })

      times = filed.messages.where(private: false).pluck(:created_at)
      ended = Time.iso8601('2026-11-07T14:03:12Z')
      expect(times).to eq([ended - 3, ended - 2, ended - 1, ended])
    end

    it 'keeps the call\'s order when two turns carry the same time' do
      same = turns.map { |turn| turn.merge(at: '2026-11-07T14:00:01Z') }

      file(turns: same)

      expect(filed.messages.where(private: false).pluck(:content)).to eq(turns.pluck(:text))
    end

    it 'keeps the record last when the AI service\'s clock runs ahead' do
      ahead = turns.each_with_index.map { |turn, index| turn.merge(at: (2.hours.from_now + index).utc.iso8601) }

      file(turns: ahead, ended_at: 3.hours.from_now.utc.iso8601)

      expect(filed.messages.last).to have_attributes(private: true, content: call[:record])
      expect(filed.messages.maximum(:created_at)).to be <= Time.current
      expect(filed.messages.where(private: false).pluck(:content)).to eq(turns.pluck(:text))
      expect(filed.reload.last_activity_at).to be <= Time.current
    end

    it 'takes a recording link of the longest length Chatwoot keeps' do
      link = "https://ai.example.com/#{'a' * 1_477}"

      file(recording_url: link)

      expect(response).to have_http_status(:created)
      expect(filed.custom_attributes['inclamo_call_recording']).to eq(link)
    end

    it 'opens a call that needs the team and resolves one that does not' do
      file
      expect(filed.status).to eq('open')

      file(call_id: 'c-18', needs_team: false, outcome: 'resolved', labels: %w[inclamo_call inclamo_resolved])
      expect(filed.status).to eq('resolved')
      expect(filed.label_list).to match_array(%w[inclamo_call inclamo_resolved])
    end

    it 'sets the priority the AI service sends, or none' do
      file(priority: 'urgent')
      expect(filed.priority).to eq('urgent')

      file(call_id: 'c-18')
      expect(filed.priority).to be_nil
    end

    it 'carries the labels and adds the ones the account does not list yet, once' do
      file(labels: %w[inclamo_call inclamo_inbound inclamo_ready_for_review])

      expect(body['labels_added']).to eq(['inclamo_ready_for_review'])
      expect(filed.label_list).to match_array(%w[inclamo_call inclamo_inbound inclamo_ready_for_review])
      expect(account.labels.find_by(title: 'inclamo_ready_for_review')).to have_attributes(description: 'Set by the AI agent', show_on_sidebar: false)

      file(call_id: 'c-18', labels: %w[inclamo_call inclamo_ready_for_review])
      expect(body['labels_added']).to eq([])
      expect(account.labels.where(title: 'inclamo_ready_for_review').count).to eq(1)
    end
  end

  describe 'the contact of a call' do
    def unchanged(contact)
      before = contact.attributes.slice('name', 'email', 'phone_number', 'identifier')
      yield
      expect(contact.reload.attributes.slice('name', 'email', 'phone_number', 'identifier')).to eq(before)
    end

    it 'is the one contact with the caller\'s number, left as it was' do
      known = create(:contact, account: account, name: 'Anna Petrova', phone_number: '+15550100002', email: nil)

      unchanged(known) { file(caller: { phone: '+15550100002', name: 'Someone else', email: 'other@example.com' }) }

      expect(body).to include('matched_by' => 'phone', 'contact_id' => known.id)
      expect(filed.contact_id).to eq(known.id)
      expect(account.contacts.count).to eq(1)
    end

    it 'is the one contact with the sent email when no contact has the number, next to their chat' do
      known = create(:contact, account: account, name: 'Anna', email: 'anna@example.com', phone_number: nil)
      chat = create(:conversation, account: account, inbox: website, contact: known)

      unchanged(known) { file(caller: { phone: '+15550100009', email: 'Anna@Example.com' }) }

      expect(body).to include('matched_by' => 'email', 'contact_id' => known.id)
      expect(known.conversations.pluck(:id)).to match_array([chat.id, filed.id])
    end

    it 'is a new contact, marked ambiguous, when two contacts have the number' do
      first = create(:contact, account: account, phone_number: '+15550100003')
      second = create(:contact, account: account, phone_number: nil)
      second.update_column(:phone_number, '+15550100003') # rubocop:disable Rails/SkipsModelValidations

      unchanged(first) { unchanged(second) { file(caller: { phone: '+15550100003', name: 'Ben' }) } }

      expect(body['matched_by']).to eq('ambiguous')
      expect([first.id, second.id]).not_to include(filed.contact_id)
      expect(filed.label_list).to include('inclamo_match_ambiguous')
      expect(filed.contact).to have_attributes(name: 'Ben', phone_number: nil)
      expect(filed.custom_attributes['inclamo_call_caller']).to eq('+15550100003')
    end

    it 'is a new contact with the number and the name for a caller nobody matches' do
      file(caller: { phone: '+15550100004', name: 'Ben', email: 'ben@example.com' })

      expect(body['matched_by']).to eq('created')
      expect(filed.contact).to have_attributes(name: 'Ben', phone_number: '+15550100004', email: 'ben@example.com', identifier: 'inclamo:customer:c-17')
    end

    it 'is "Unknown caller" for a caller without a name' do
      file(caller: { phone: '+15550100004' })

      expect(filed.contact.name).to eq('Unknown caller')
    end

    it 'is a new contact marked as having no caller id when the call has neither number nor email' do
      file(caller: nil)

      expect(body['matched_by']).to eq('anonymous')
      expect(filed.contact).to have_attributes(name: 'Unknown caller', phone_number: nil, email: nil)
      expect(filed.label_list).to include('inclamo_no_caller_id')
    end

    it 'is "Website visitor" for a call from the storefront button without a name' do
      file(entry: 'web', line: nil, caller: {})

      expect(filed.contact.name).to eq('Website visitor')
      expect(filed.custom_attributes).not_to have_key('inclamo_call_line')
    end

    it 'uses the contact\'s place in the Phone inbox again for their next call' do
      file
      first = filed
      file(call_id: 'c-18')

      expect(filed.contact_id).to eq(first.contact_id)
      expect(filed.contact_inbox_id).to eq(first.contact_inbox_id)
      expect(filed.id).not_to eq(first.id)
    end
  end

  describe 'one call, one conversation' do
    it 'answers a repeat with the conversation filed first and changes nothing' do
      file
      first = body
      rows = -> { [Conversation.count, Message.count, Contact.count, Label.count, Inclamo::CallConversation.count] }
      before = rows.call

      file(record: 'Another record', turns: [], needs_team: false, labels: %w[inclamo_call inclamo_other])

      expect(response).to have_http_status(:ok)
      expect(body).to eq(first.merge('found' => true, 'labels_added' => []))
      expect(rows.call).to eq(before)
      expect(filed.status).to eq('open')
    end

    it 'gives one conversation when the same call is filed at the same moment' do
      file
      first = body['conversation_id']
      filing = Inclamo::Ai::Calls::Filing.read(call.deep_stringify_keys)
      service = Inclamo::Ai::Calls::FileCall.new(account: account, connection: record, bot: bot, filing: filing)
      # The other filing committed between this one's look and its own key.
      looks = 0
      allow(service).to receive(:earlier).and_wrap_original do |original|
        looks += 1
        looks == 1 ? nil : original.call
      end

      result = nil
      expect { result = service.call }.not_to(change { [Conversation.count, Message.count, Contact.count] })

      expect(result).to have_attributes(found: true)
      expect(result.conversation.display_id).to eq(first)
      expect(looks).to eq(2)
    end

    it 'answers a repeat with the contact the conversation is on now' do
      file
      conversation = filed
      other = create(:contact, account: account)
      conversation.update!(contact: other, contact_inbox: create(:contact_inbox, contact: other, inbox: phone_inbox))

      file

      expect(body).to include('found' => true, 'contact_id' => other.id)
    end

    it 'files a call again after its conversation was deleted' do
      file
      filed.destroy!

      file

      expect(response).to have_http_status(:created)
      expect(body).to include('found' => false, 'matched_by' => 'phone')
    end

    it 'answers invalid_call, without the content, when Chatwoot refuses a record' do
      allow_any_instance_of(Inclamo::Ai::Calls::FileCall).to receive(:file).and_raise(ActiveRecord::RecordInvalid.new(Contact.new.tap { |c| c.errors.add(:email, 'anna@example.com is taken') })) # rubocop:disable RSpec/AnyInstance

      file

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include('code' => 'invalid_call')
      expect(response.body).not_to include('anna@example.com')
    end

    it 'keeps calls with the same id of two accounts apart' do
      file
      other = create(:account)
      other_record = connect_ai_agent(other, [])

      post "/api/v1/accounts/#{other.id}/inclamo/calls", params: call,
                                                         headers: { 'api_access_token' => AgentBot.find(other_record.agent_bot_id).access_token.token }, as: :json

      expect(response).to have_http_status(:created)
      expect(other.conversations.count).to eq(1)
    end

    it 'leaves nothing behind when a step fails' do
      allow_any_instance_of(Inclamo::Ai::Calls::FileCall).to receive(:write_record).and_raise(ActiveRecord::StatementInvalid) # rubocop:disable RSpec/AnyInstance

      file

      expect(response).to have_http_status(:internal_server_error)
      nothing_filed
      expect(account.contacts.count).to eq(0)
    end
  end

  describe 'what is refused' do
    def refused(code, overrides)
      file(**overrides)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to include('error' => code, 'code' => code)
      nothing_filed
    end

    it 'refuses a filing without a call id, or with one of another form' do
      refused('invalid_call', call_id: nil)
      refused('invalid_call', call_id: 'call 17')
      refused('invalid_call', call_id: 'c' * 101)
    end

    it 'refuses fields that break their rule' do
      refused('invalid_call', entry: 'sms')
      refused('invalid_call', line: '5550100100')
      refused('invalid_call', caller: { phone: '555-0100' })
      refused('invalid_call', caller: { email: 'not an email' })
      refused('invalid_call', caller: { name: 'A' * 256 })
      refused('invalid_call', ended_at: 'yesterday')
      refused('invalid_call', ended_at: nil)
      refused('invalid_call', duration: -1)
      refused('invalid_call', duration: '192')
      refused('invalid_call', outcome: nil)
      refused('invalid_call', outcome: 'Not A Word')
      refused('invalid_call', needs_team: nil)
      refused('invalid_call', priority: 'highest')
      refused('invalid_call', recording_url: 'http://ai.example.com/calls/c-17')
      refused('invalid_call', recording_url: "https://ai.example.com/#{'a' * 1_500}")
      refused('invalid_call', duration: 1_000_001)
      refused('invalid_call', ended_at: '2026-11-07T14:03:12')
      refused('invalid_call', ended_at: '999999-11-07T14:03:12Z')
      refused('invalid_call', record: "Summary\u0000")
      refused('invalid_call', turns: [{ role: 'caller', text: "Hi\u0000" }])
      refused('invalid_call', caller: { name: "Anna\u0000" })
      refused('invalid_call', turns: [{ role: 'robot', text: 'Hi' }])
      refused('invalid_call', turns: [{ role: 'caller', text: '' }])
      refused('invalid_call', turns: [{ role: 'caller', text: 'Hi', at: 'noon' }])
      refused('invalid_call', record: nil)
      refused('invalid_call', labels: Array.new(21) { |index| "inclamo_l#{index}" })
    end

    it 'refuses a label of someone else\'s or of another form' do
      refused('invalid_label', labels: %w[inclamo_call vip])
      refused('invalid_label', labels: ['inclamo_Call'])
      refused('invalid_label', labels: ['inclamo_'])
      expect(account.labels.where(title: 'vip')).to be_empty
    end

    it 'refuses a filing too large, whole' do
      refused('too_large', turns: Array.new(501) { { role: 'caller', text: 'Hi' } })
      refused('too_large', turns: [{ role: 'caller', text: 'a' * 10_001 }])
      refused('too_large', record: 'a' * 8_001)
    end

    it 'takes a filing at the limits' do
      file(turns: Array.new(500) { |index| { role: index.even? ? 'agent' : 'caller', text: 'a' * 20 } }, record: 'a' * 8_000)

      expect(response).to have_http_status(:created)
      expect(filed.messages.count).to eq(501)
      expect(filed.messages.last.private).to be(true)
    end

    it 'never repeats a part of the call in a refusal or in the log' do
      logged = []
      allow(Rails.logger).to receive(:info) { |*args, &block| logged << (args.first || block&.call).to_s }

      file(priority: 'highest', caller: { phone: '+15550100001', email: 'anna@example.com', name: 'Anna Secret' })

      expect(response).to have_http_status(:unprocessable_entity)
      text = response.body + logged.join("\n")
      ['missing from my order', '+15550100001', 'anna@example.com', 'Anna Secret', 'Summary'].each do |part|
        expect(text).not_to include(part)
      end
      expect(logged.join("\n")).to include('call c-17 refused: invalid_call')
    end

    it 'hides the call\'s content from the request log' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      shown = filter.filter(call.deep_stringify_keys.merge('recording_url' => 'https://ai.example.com/calls/c-17'))

      expect(shown.slice('turns', 'record', 'caller', 'line', 'recording_url').values.uniq).to eq(['[FILTERED]'])
      expect(shown).to include('call_id' => 'c-17', 'outcome' => 'request')
      expect(filter.filter('returns' => 'kept', 'records' => 'kept')).to eq('returns' => 'kept', 'records' => 'kept')
    end
  end

  describe 'card numbers' do
    it 'stores none: in a turn, in the record and in the name' do
      file(
        caller: { phone: '+15550100001', name: 'Anna 4111 1111 1111 1111' },
        turns: [{ role: 'caller', text: 'my card is 4111 1111 1111 1111' }, { role: 'agent', text: 'Noted 4111-1111-1111-1111.' }],
        record: 'Card 4111111111111111 was read out.'
      )

      expect(filed.messages.pluck(:content)).to eq(['my card is [card number removed]', 'Noted [card number removed].', 'Card [card number removed] was read out.'])
      expect(filed.messages.pluck(:processed_message_content).join).not_to include('4111')
      expect(filed.contact.name).to eq('Anna [card number removed]')
    end

    it 'keeps an order number that fails the Luhn check' do
      file(turns: [{ role: 'caller', text: 'order 1001234567890' }])

      expect(filed.messages.first.content).to eq('order 1001234567890')
    end
  end

  describe 'filing reaches nobody' do
    before do
      create(:inbox_member, inbox: phone_inbox, user: agent)
      phone_inbox.update!(enable_auto_assignment: true)
      # Chatwoot assigns to agents who are online.
      OnlineStatusTracker.update_presence(account.id, 'User', agent.id)
      OnlineStatusTracker.set_status(account.id, agent.id, 'online')
    end

    it 'sends nothing, wakes no agent bot and notifies the assignee of the conversation, not of its turns' do
      long = Array.new(40) { |index| { role: index.even? ? 'agent' : 'caller', text: "Turn #{index}" } }
      deliveries = stub_request(:any, /ai\.example\.com/)
      # Chatwoot looks for a picture of a new contact with an email.
      stub_request(:get, /gravatar\.com/).to_return(status: 404)

      perform_enqueued_jobs { file(turns: long, caller: { phone: '+15550100001', email: 'anna@example.com', name: 'Anna' }) }

      expect(response).to have_http_status(:created)
      conversation = filed
      expect(conversation.assignee_id).to eq(agent.id)
      expect(conversation.reload.status).to eq('open')
      kinds = Notification.where(user: agent).pluck(:notification_type)
      expect(kinds).to include('conversation_assignment')
      expect(kinds).not_to include('assigned_conversation_new_message')
      expect(Notification.where(secondary_actor_type: 'Message', secondary_actor_id: conversation.messages.where(private: false).select(:id))).to be_empty
      expect(deliveries).not_to have_been_requested
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'queues a send job for the note alone and none for the turns' do
      expect { file }.to have_enqueued_job(SendReplyJob).exactly(:once)

      note = filed.messages.find_by(private: true)
      expect(SendReplyJob).to have_been_enqueued.with(note.id)
    end

    it 'defines the attributes of a call for an account connected before they existed' do
      file

      keys = Inclamo::Ai::Calls::Attributes::DEFINITIONS.keys
      expect(account.custom_attribute_definitions.conversation_attribute.where(attribute_key: keys).count).to eq(8)
      expect { file(call_id: 'c-18') }.not_to change(CustomAttributeDefinition, :count)
    end

    it 'leaves a resolved call resolved' do
      perform_enqueued_jobs { file(needs_team: false, outcome: 'resolved') }

      expect(filed.reload.status).to eq('resolved')
    end
  end
end
