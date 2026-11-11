# frozen_string_literal: true

raise 'Only the isolated support network is allowed' unless ENV['INCLAMO_SUPPORT_ENDPOINT'] == 'http://support-proxy:8080/inclamo/support/v1' && ENV['INCLAMO_SUPPORT_TEST_NETWORK'] == 'true'
raise 'Enterprise code must be absent' if Rails.root.join('enterprise').exist?

password = 'Synthetic-theme-only-123!'
if Inclamo::Support.central?
  account = Account.find_or_create_by!(name: 'Synthetic Inclamo Support')
  user = User.find_or_initialize_by(email: 'support-admin@example.test')
  user.assign_attributes(name: 'Synthetic Support Agent', password: password, password_confirmation: password, confirmed_at: Time.current)
  user.save!
  AccountUser.find_or_create_by!(account: account, user: user) { |member| member.role = :administrator }
  inbox = account.inboxes.find_or_create_by!(name: 'Inclamo Support') { |record| record.channel = Channel::Api.create!(account: account) }
  InboxMember.find_or_create_by!(inbox: inbox, user: user)
  raise 'The fresh fixture must bind the configured account and inbox' unless inbox.id.to_s == ENV['INCLAMO_SUPPORT_INBOX_ID'] && account.id.to_s == ENV['INCLAMO_SUPPORT_ACCOUNT_ID']
else
  account = Account.find_by!(name: 'Inclamo Theme Example')
  other = User.find_or_initialize_by(email: 'support-other@example.test')
  other.assign_attributes(name: 'Synthetic Other Agent', password: password, password_confirmation: password, confirmed_at: Time.current)
  other.save!
  AccountUser.find_or_create_by!(account: account, user: other) { |member| member.role = :agent }
  account.inboxes.each { |inbox| InboxMember.find_or_create_by!(inbox: inbox, user: other) }
  second = Account.find_or_create_by!(name: 'Synthetic Other Account')
  AccountUser.find_or_create_by!(account: second, user: other) { |member| member.role = :agent }
  %w[theme-admin theme-agent].each do |name|
    user = User.find_by!(email: "#{name}@example.test")
    AccountUser.find_or_create_by!(account: second, user: user) { |member| member.role = name == 'theme-admin' ? :administrator : :agent }
  end
end
Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
puts "SUPPORT_FIXTURE_ACCOUNT=#{account.id}"
