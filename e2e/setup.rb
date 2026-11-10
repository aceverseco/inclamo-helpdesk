# frozen_string_literal: true

# Prepares a fresh helpdesk for the end-to-end tests: one account, an
# administrator and an agent with the passwords given in the environment, and
# the installation's first-run page closed. Fed to `rails runner -` by
# e2e/run.sh; safe to run again.
account = Account.find_or_create_by!(name: 'E2E')
{ 'ADMIN' => :administrator, 'AGENT' => :agent }.each do |key, role|
  email = ENV.fetch("STAND_#{key}_EMAIL")
  password = ENV.fetch("STAND_#{key}_PASSWORD")
  user = User.find_by(email: email) || User.new(email: email, name: "E2E #{key.capitalize}")
  user.assign_attributes(password: password, password_confirmation: password, confirmed_at: Time.current)
  user.save!
  AccountUser.find_or_create_by!(account: account, user: user) { |member| member.role = role }
end

# An empty account for onboarding; no customer channel or conversation exists.
setup_account = Account.find_or_create_by!(name: 'E2E Setup')
admin = User.find_by!(email: ENV.fetch('STAND_ADMIN_EMAIL'))
AccountUser.find_or_create_by!(account: setup_account, user: admin) { |member| member.role = :administrator }

# Until this flag is gone, Chatwoot serves a page on which anyone who reaches
# the instance can create its super administrator.
Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)

puts "E2E_ACCOUNT_ID=#{account.id}"
