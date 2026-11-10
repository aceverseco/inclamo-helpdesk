# frozen_string_literal: true

class Inclamo::AiIdentityVerification < ApplicationRecord
  belongs_to :account
  belongs_to :contact_inbox
  belongs_to :user
  validates :contact_inbox_id, uniqueness: { scope: :account_id }

  def self.digest_for(conversation)
    contact = conversation.contact.reload
    Inclamo::Ai::OrderAuthority.digest([contact.id, contact.email, contact.phone_number, contact.identifier,
                                       contact.custom_attributes.to_h[Inclamo::Shopify::CustomerMatcher::REMEMBERED]])
  end

  def self.verified?(conversation, customer_id, customer_email: nil)
    # Chatwoot signs the identifier, not arbitrary widget email fields. Bind
    # that signed identifier to the matched Shopify customer.
    contact = conversation.contact.reload
    if conversation.contact_inbox&.reload&.hmac_verified?
      return true if contact.identifier == customer_id || (customer_email.present? && contact.identifier == customer_email)
    end

    exists?(account_id: conversation.account_id, contact_inbox_id: conversation.contact_inbox_id,
            customer_id: customer_id, identity_digest: digest_for(conversation))
  end
end
