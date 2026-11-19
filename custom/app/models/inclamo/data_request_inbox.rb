# frozen_string_literal: true

# Which inbox of an account is its "Data requests" inbox, and which contact
# its tickets belong to (Inclamo::Erasure::Ticket). One per account.
class Inclamo::DataRequestInbox < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact, optional: true

  # Whether conversations of this inbox are tickets about shoppers: they are
  # kept out of the SLA timers (Inclamo::Sla::Timers).
  def self.ticket_inbox?(inbox_id)
    inbox_id.present? && exists?(inbox_id: inbox_id)
  end
end
