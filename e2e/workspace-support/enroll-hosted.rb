# frozen_string_literal: true

raise 'Synthetic support fixture only' unless ENV['INCLAMO_SUPPORT_TEST_NETWORK'] == 'true' && ENV['FRONTEND_URL'] == 'http://hosted:3000'
Inclamo::Support::Transport.new.enroll!
identity = Inclamo::Support::Installation.identity
puts "#{identity.source_id},#{Inclamo::Support::Authentication.fingerprint(identity.public_key)}"
