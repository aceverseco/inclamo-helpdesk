# frozen_string_literal: true
# Only run on the disposable theme stack. Every identity and credential is synthetic.
raise 'Theme fixtures require the isolated fixture service' unless ENV['INCLAMO_SHOPIFY_BASE_URL'] == 'http://shopify-fixture:8080'

account = Account.find_or_create_by!(name: 'Inclamo Theme Example')
%w[admin agent].each do |role|
  user = User.find_or_initialize_by(email: "theme-#{role}@example.test")
  user.assign_attributes(name: "Example #{role.capitalize}", password: 'Synthetic-theme-only-123!', password_confirmation: 'Synthetic-theme-only-123!', confirmed_at: Time.current)
  user.save!
  AccountUser.find_or_create_by!(account: account, user: user) { |member| member.role = role == 'admin' ? :administrator : :agent }
end
# Repeatable dataset; this account exists only on the isolated fixture stack.
account.conversations.destroy_all
account.contacts.destroy_all
Portal.find_or_create_by!(account: account, slug: 'theme-example') do |portal|
  portal.name = 'Example Help Centre'
  portal.config = { allowed_locales: ['en'] }
end
connection = Inclamo::ShopifyConnection.find_or_initialize_by(account: account)
connection.assign_attributes(shop_domain: 'theme-fixture.myshopify.com', shop_name: 'Example Store', shop_currency: 'UAH', auth_kind: 'legacy_token', access_token: 'synthetic-token-not-valid-anywhere', api_version: Inclamo::Shopify::API_VERSION, status: 'working', customer_data_mode: 'full', scopes: %w[read_customers read_orders write_orders write_draft_orders read_products])
connection.save!
admin = User.find_by!(email: 'theme-admin@example.test')
agent = User.find_by!(email: 'theme-agent@example.test')
admin.update!(ui_settings: {}, type: 'SuperAdmin')
agent.update!(ui_settings: {})
inbox = account.inboxes.find_or_create_by!(name: 'E2E') do |box|
  box.channel = Channel::Api.create!(account: account, identifier: 'theme-example-channel')
end
inbox.channel.update!(identifier: 'theme-example-channel')
[admin, agent].each { |user| InboxMember.find_or_create_by!(inbox: inbox, user: user) }
conversations = [
  ['Maya Example', 'maya.example.t001@example.com', 'Hello, could you help with order #1001?'],
  ['Alex Example', 'alex.theme@example.test', 'Thank you for your help.'],
  ['Emma Example', 'emma.theme@example.test', 'Will this be available in blue?'],
  ['Oliver Example', 'oliver.theme@example.test', 'Can I exchange this for another size?'],
  ['Isabella Example', 'isabella.theme@example.test', 'Could you include a gift note?'],
  ['Noah Example', 'noah.theme@example.test', 'When will my package arrive?'],
  ['Amelia Example', 'amelia.theme@example.test', 'Could you help me choose the right size?'],
  ['Lucas Example', 'lucas.theme@example.test', 'I would like to update my delivery details.']
].each_with_index.map do |(name, email, text), index|
  contact = account.contacts.create!(name: name, email: email)
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: "theme-example-#{index}")
  conversation = account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: contact_inbox, assignee: admin)
  # Distinct timestamps keep the native conversation sort deterministic.
  fixture_time = Time.utc(2026, 11, 9, 10) - index * 3600
  conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: text, created_at: fixture_time)
  if index.zero?
    conversation.messages.create!(account: account, inbox: inbox, sender: admin, message_type: :outgoing, content: 'Hi Maya! Your order has not shipped yet, so we can help. Could you send me the new address?', created_at: fixture_time + 120)
    conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: 'Thanks! The new address is 24 Maple Street, Brooklyn, NY 11201. Really appreciate your help!', created_at: fixture_time + 240)
  end
  conversation.update_columns(display_id: index + 1, created_at: fixture_time, last_activity_at: fixture_time)
  { id: conversation.display_id, contactId: contact.id }
end
widget = Channel::WebWidget.find_or_create_by!(account: account, website_token: 'synthetic-theme-widget') do |channel|
  channel.website_url = 'https://example.test'
  channel.welcome_title = 'Example support'
  channel.welcome_tagline = 'How can we help?'
end
widget_inbox = account.inboxes.find_or_create_by!(name: 'Example Website') { |box| box.channel = widget }
survey_contact = account.contacts.create!(name: 'Survey Example', email: 'survey@example.test')
survey_contact_inbox = ContactInbox.create!(contact: survey_contact, inbox: widget_inbox, source_id: 'synthetic-survey')
survey = account.conversations.create!(inbox: widget_inbox, contact: survey_contact, contact_inbox: survey_contact_inbox, status: :resolved)
survey.messages.create!(account: account, inbox: widget_inbox, sender: admin, message_type: :outgoing, content_type: :input_csat, content: 'Please rate your experience')
Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
puts "THEME_ACCOUNT_ID=#{account.id}"
puts "THEME_DATA=#{JSON.generate({ inbox: { id: inbox.id }, conversation: conversations.first, second: conversations[1], survey: survey.uuid })}"
