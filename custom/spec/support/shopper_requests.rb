# frozen_string_literal: true

require Rails.root.join('custom/spec/support/erasure_requests')

# Plays the store app's requests about one shopper (docs/app-store-erasure.md
# §4–§6) in specs, and makes a store's shoppers with their conversations.
module ShopperRequests
  include ErasureRequests

  SHOPPER = { email: 'pat@example.com', phone: '+15556251199' }.freeze

  def ask_shopper_erasure(domain = ProvisioningRequests::STORE, shopper: SHOPPER, order_ids: nil, body: nil, **)
    provisioning_call(:post, domain, body: body || shopper_body(shopper, order_ids), suffix: '/shoppers/erasure', **)
  end

  def ask_data_request(domain = ProvisioningRequests::STORE, shopper: SHOPPER, order_ids: nil, body: nil, **)
    provisioning_call(:post, domain, body: body || shopper_body(shopper, order_ids), suffix: '/shoppers/data-request', **)
  end

  def ask_shopper_counts(domain = ProvisioningRequests::STORE, **)
    provisioning_call(:get, domain, suffix: '/shoppers/requests', **)
  end

  def shopper_body(shopper, order_ids)
    { contract: 1, shopper: shopper }.merge(order_ids ? { order_ids: order_ids } : {})
  end

  # A store whose account the app provisioned and that is active.
  def active_store(domain = ProvisioningRequests::STORE, **)
    provision(domain, **)
    provisioned(domain)
  end

  # A shopper of the account: a contact with `conversations` conversations in
  # a chat inbox of the account.
  def shopper_contact(account, email: SHOPPER[:email], phone: SHOPPER[:phone], conversations: 2, inbox: nil, **attributes)
    inbox ||= create(:inbox, account: account)
    contact = create(:contact, account: account, email: email, phone_number: phone, **attributes)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create_list(:conversation, conversations, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    contact
  end

  def shopper_request(kind = 'shopper_erasure', domain = ProvisioningRequests::STORE)
    Inclamo::ErasureRequest.where(kind: kind, shop_domain: domain).order(:id).last
  end

  def ticket_of(request)
    Conversation.find(request.reload.conversation_id)
  end

  # The ticket's messages, oldest first.
  def ticket_texts(request)
    Message.where(conversation_id: request.reload.conversation_id).reorder(:id).pluck(:content)
  end

  def data_requests_inbox(account)
    Inclamo::DataRequestInbox.find_by(account_id: account.id)&.inbox
  end

  # The administrator the app named for the account.
  def store_administrator
    User.from_email('alex@example.test')
  end

  def shopper_path(account, request, action = nil)
    ["/api/v1/accounts/#{account.id}/inclamo/shopper_requests/#{request.id}", action].compact.join('/')
  end
end
