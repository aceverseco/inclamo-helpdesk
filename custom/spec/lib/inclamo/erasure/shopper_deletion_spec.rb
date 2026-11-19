# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('custom/spec/support/shopper_requests')
require Rails.root.join('custom/spec/support/ai_service_stubs')

# What deleting one shopper's data removes (docs/app-store-erasure.md §4.2):
# the contacts that match at that moment, whole, with their conversations,
# messages and files, and what the overlay keeps about them and about the
# orders the request lists.
RSpec.describe Inclamo::Erasure::ShopperDeletion, type: :request do
  include_context 'with app provisioning'
  include ShopperRequests
  include AiServiceStubs

  let(:now) { Time.utc(2026, 11, 20, 10, 0, 0) }
  let(:account) { provisioned.account }
  let(:inbox) { create(:inbox, account: account) }
  before { active_store }

  let!(:shopper) { shopper_contact(account, inbox: inbox) }

  around { |example| travel_to(now) { example.run } }


  def erasure(**)
    ask_shopper_erasure(**)
    expect(response.parsed_body['state']).to eq('waiting')
    shopper_request
  end

  def delete!(request)
    perform_enqueued_jobs { Inclamo::Erasure::ShopperActions.delete!(request, store_administrator) }
  end

  it 'destroys the contact whole: its conversations, messages, files and contact inboxes, and keeps the ticket' do
    conversation = shopper.conversations.first
    message = create(:message, :with_attachment, account: account, inbox: inbox, conversation: conversation, sender: shopper,
                                                 message_type: :incoming)
    blob = message.attachments.first.file.blob
    create(:note, account: account, contact: shopper, user: store_administrator)
    request = erasure

    delete!(request)

    expect(Contact.exists?(shopper.id)).to be(false)
    expect(Conversation.where(contact_id: shopper.id)).to be_empty
    expect(Message.where(conversation_id: shopper.conversations.ids + [conversation.id])).to be_empty
    expect(Message.where(sender_type: 'Contact', sender_id: shopper.id)).to be_empty
    expect(Attachment.where(message_id: message.id)).to be_empty
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(false)
    expect(ContactInbox.where(contact_id: shopper.id)).to be_empty
    expect(Note.where(contact_id: shopper.id)).to be_empty
    expect(ticket_of(request)).to be_present
  end

  it 'deletes, never blanks: no contact keeps the shopper\'s email or phone' do
    request = erasure

    delete!(request)

    expect(Contact.where(account_id: account.id).where('LOWER(email) = ?', 'pat@example.com')).to be_empty
    expect(Contact.where(account_id: account.id, phone_number: '+15556251199')).to be_empty
    expect(Contact.where(account_id: account.id).pluck(:name)).to eq(['Shopify data requests'])
  end

  it 'deletes a contact who is online' do
    OnlineStatusTracker.update_presence(account.id, 'Contact', shopper.id)
    expect(OnlineStatusTracker.get_presence(account.id, 'Contact', shopper.id)).to be_truthy

    delete!(erasure)

    expect(Contact.exists?(shopper.id)).to be(false)
  end

  it 'deletes a conversation the shopper started after the ticket was made, and a second contact found by the phone' do
    request = erasure
    travel 1.day
    later = create(:conversation, account: account, inbox: inbox, contact: shopper)
    # The shopper wrote from another email too, giving the phone there.
    shopper.update!(phone_number: nil)
    by_phone = create(:contact, account: account, email: 'pat.other@example.com', phone_number: '+15556251199')
    by_phone_conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: by_phone)

    delete!(request)

    expect(Conversation.exists?(later.id)).to be(false)
    expect(Contact.exists?(by_phone.id)).to be(false)
    expect(Conversation.exists?(by_phone_conversation.id)).to be(false)
  end

  it 'deletes in a suspended account' do
    request = erasure
    remove_app
    expect(account.reload).to be_suspended

    delete!(request)

    expect(Contact.exists?(shopper.id)).to be(false)
    expect(request.reload.state).to eq('done')
  end

  it 'leaves other shoppers and other accounts alone' do
    other_shopper = shopper_contact(account, email: 'kim@example.com', phone: '+15550000002', inbox: inbox)
    provision('other-store.myshopify.com', admin: { email: 'sam@example.test' })
    elsewhere = shopper_contact(provisioned('other-store.myshopify.com').account)

    delete!(erasure)

    expect(Contact.exists?(other_shopper.id)).to be(true)
    expect(other_shopper.conversations.count).to eq(2)
    expect(Contact.exists?(elsewhere.id)).to be(true)
  end

  describe 'the overlay\'s rows (REACH)' do
    let(:conversation) { shopper.conversations.first }
    let(:contact_inbox) { conversation.contact_inbox }

    it 'names every table of the overlay that names a contact, a conversation or an order, as the erasure\'s list does' do
      about_shoppers = Inclamo::Erasure::References::LIST.select { |_table, columns| columns.keys.any? { |column| column != 'account_id' } }.keys
      expect(described_class::REACH.keys).to match_array(about_shoppers)
      expect(described_class::REACH.values.uniq - %i[deleted with_conversation not_a_shopper kept]).to eq([])
      described_class::REACH.select { |_table, reach| reach == :with_conversation }.each_key do |table|
        expect(Inclamo::Erasure::References::LIST.fetch(table)['conversation_id']).to eq(:cascade)
      end
    end

    it 'inclamo_ai_proposals: the AI agent\'s proposals in the shopper\'s conversations' do
      connection = connect_ai_agent(account, [inbox])
      Inclamo::AiProposal.insert!({ account_id: account.id, conversation_id: conversation.id, agent_bot_id: connection.agent_bot_id,
                                    request_id: 'request-1', request_digest: 'digest', review_digest: 'digest', action: 'cancel',
                                    payload: '{}', expires_at: 1.day.from_now })

      delete!(erasure)

      expect(Inclamo::AiProposal.where(conversation_id: conversation.id)).to be_empty
      expect(Conversation.exists?(conversation.id)).to be(false)
    end

    it 'inclamo_ai_identity_verifications: the shopper\'s verified identities' do
      Inclamo::AiIdentityVerification.insert!({ account_id: account.id, contact_inbox_id: contact_inbox.id, user_id: store_administrator.id,
                                                customer_id: 'gid://shopify/Customer/1', identity_digest: 'digest' })

      delete!(erasure)

      expect(Inclamo::AiIdentityVerification.where(account_id: account.id)).to be_empty
      expect(ContactInbox.exists?(contact_inbox.id)).to be(false)
    end

    it 'inclamo_call_conversations: the keys of the shopper\'s calls' do
      Inclamo::CallConversation.insert!({ account_id: account.id, call_id: 'call-1', conversation_id: conversation.id,
                                          contact_id: shopper.id, created_at: Time.current })
      Inclamo::CallConversation.insert!({ account_id: account.id, call_id: 'call-2', conversation_id: nil, contact_id: shopper.id,
                                          created_at: Time.current })

      delete!(erasure)

      expect(Inclamo::CallConversation.where(account_id: account.id)).to be_empty
    end

    it 'inclamo_order_actions: actions in the shopper\'s conversations and on the listed orders' do
      other = shopper_contact(account, email: 'kim@example.com', phone: '+15550000002', inbox: inbox).conversations.first
      action = lambda do |id, conversation_id, order_id|
        Inclamo::OrderAction.insert!({ account_id: account.id, conversation_id: conversation_id, user_id: store_administrator.id,
                                       action_id: id, action: 'cancel', order_id: order_id })
      end
      action.call('in-conversation', conversation.id, 'gid://shopify/Order/1')
      action.call('listed-order', other.id, 'gid://shopify/Order/299938')
      action.call('kept', other.id, 'gid://shopify/Order/2')

      delete!(erasure(order_ids: ['299938']))

      expect(Inclamo::OrderAction.where(account_id: account.id).pluck(:action_id)).to eq(['kept'])
    end

    it 'inclamo_sla_timers: the timers of the shopper\'s conversations' do
      policy = Inclamo::SlaPolicy.create!(account: account, name: 'Standard', first_response_seconds: 3600, all_inboxes: true,
                                          business_hours_only: false, created_at: 1.day.ago)
      Inclamo::Sla::Timers.apply!(conversation)
      expect(Inclamo::SlaTimer.where(conversation_id: conversation.id, policy: policy)).to exist

      delete!(erasure)

      expect(Inclamo::SlaTimer.where(conversation_id: conversation.id)).to be_empty
    end

    it 'forgets the account\'s cached store answers' do
      Inclamo::Shopify::OrderReader.forget!(account.id)
      generation = Redis::Alfred.get(Inclamo::Shopify::OrderReader.generation_key(account.id))

      delete!(erasure)

      expect(Redis::Alfred.get(Inclamo::Shopify::OrderReader.generation_key(account.id))).not_to eq(generation)
    end
  end
end
