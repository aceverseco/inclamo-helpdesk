# frozen_string_literal: true

# Use the configured ActionMailer transport, but keep support's retry behavior
# independent of the native mailer's swallowed SMTP exceptions and templates.
class Inclamo::Support::Mailer < ActionMailer::Base
  default from: ENV.fetch('MAILER_SENDER_EMAIL', 'Inclamo <support@example.test>')

  def verification(email, code)
    mail(to: email, subject: 'Verify your Inclamo support notifications') do |format|
      format.text { render plain: "Your notification verification code is #{code}. It expires in 15 minutes.\nIf you did not request this, ignore this email." }
    end
  end

  def notification(delivery)
    mapping = delivery.central_request
    source = mapping.source
    account_id = mapping.account_key.delete_prefix('account:')
    link = "#{Inclamo::Support.valid_url!(source.base_url)}/app/accounts/#{account_id}/dashboard?support_request=#{mapping.local_reference}"
    mail(to: delivery.recipient.email, subject: 'A new reply from Inclamo support',
         message_id: "inclamo-support-#{delivery.id}@notifications.inclamo.com") do |format|
      format.text { render plain: "Inclamo support has replied to your request.\nSign in to read it: #{link}\n\nThis email is a notification. Reply in the product." }
    end
  end
end
