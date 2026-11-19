# frozen_string_literal: true

module Inclamo
  module Erasure
    # The store app's two requests about one shopper
    # (docs/app-store-erasure.md §4, §5): Shopify asked to erase the shopper,
    # or to give the store owner the shopper's data. Neither deletes anything.
    #
    # The shopper is looked for in the store's account only (Shoppers). The
    # newest request of the same kind for the same shopper (the same digests)
    # in that account decides the answer:
    # - one that is not done is answered with its state, and nothing changes:
    #   the date of an erasure does not move;
    # - one that is done is answered `done` while nothing matches any longer,
    #   and a new ticket is made when something matches again;
    # - without one, a match makes a ticket (Ticket) and no match makes none.
    # A store without an account is answered as a shopper nothing is held of.
    # No answer holds the shopper's email, phone or name, a hold's reason, an
    # administrator or a message.
    #
    # Answers Answer(outcome:, body:); the outcome is the one recorded among
    # the store app's attempts (Inclamo::ProvisioningEvent).
    class ShopperRequest
      Answer = Struct.new(:outcome, :body, keyword_init: true)
      OUTCOMES = {
        'shopper_erasure' => { made: 'shopper_ticket_made', found: 'shopper_ticket_found', none: 'shopper_none' },
        'shopper_data_request' => { made: 'data_request_made', found: 'data_request_found', none: 'data_request_none' }
      }.freeze

      # `payload` is a Provisioning::ShopperPayload.
      def initialize(shop_domain, kind, payload, now: Time.current)
        @shop_domain = shop_domain
        @kind = kind
        @payload = payload
        @now = now
        @outcomes = OUTCOMES.fetch(kind)
      end

      def call
        row = Provisioning.store_domain(@shop_domain) && ProvisionedAccount.for_store(@shop_domain)
        return none unless row

        row.with_lock do
          account = row.account if row.active? || row.suspended?
          next none unless account

          answer_for(row, account)
        end
      end

      private

      def answer_for(row, account)
        earlier = latest(row, account)
        return found(earlier, row, account, contacts(account)) if earlier && !earlier.done?

        matched = contacts(account)
        return earlier ? found(earlier, row, account, matched) : none if matched.empty?

        made(row, account, matched)
      end

      def contacts(account)
        Shoppers.matching(account, email: @payload.email, phone: @payload.phone).to_a
      end

      def digests
        { email_digest: Shoppers.digest(Shoppers.email(@payload.email)), phone_digest: Shoppers.digest(Shoppers.digits(@payload.phone)) }
      end

      def latest(row, account)
        Inclamo::ErasureRequest.where(kind: @kind, shop_domain: row.shop_domain, account_id: account.id, **digests).order(:id).last
      end

      def made(row, account, matched)
        delete_after = (@now + Erasure.shopper_wait).change(usec: 0) if @kind == 'shopper_erasure'
        request = Inclamo::ErasureRequest.create!(
          kind: @kind, shop_domain: row.shop_domain, account_id: account.id, state: 'waiting', received_at: @now,
          email: @payload.email, phone: @payload.phone, order_ids: @payload.order_ids, delete_after: delete_after, **digests
        )
        conversations = Shoppers.conversation_count(matched)
        Ticket.open!(request, account, contacts: matched.size, conversations: conversations)
        Answer.new(outcome: @outcomes[:made], body: body(request, row, account, matched.size, conversations))
      end

      def found(request, row, account, matched)
        Answer.new(outcome: @outcomes[:found], body: body(request, row, account, matched.size, Shoppers.conversation_count(matched)))
      end

      def none
        body = { contract: Provisioning::CONTRACT, state: 'none', contacts: 0 }
        body[:conversations] = 0 if @kind == 'shopper_data_request'
        Answer.new(outcome: @outcomes[:none], body: body)
      end

      def body(request, row, account, contacts, conversations)
        base = { contract: Provisioning::CONTRACT, state: request.state }
        return base.merge(contacts: contacts, conversations: conversations, account_state: account_state(row, account)) if request.data_request?

        case request.state
        when 'waiting' then base.merge(contacts: contacts, conversations: conversations, delete_after: time(request.delete_after))
        when 'held' then base.merge(held_at: time(request.held_at))
        else base.merge(done_at: time(request.completed_at), done_by: request.done_by == 'team' ? 'team' : 'automatic')
        end
      end

      def account_state(row, account)
        row.suspended? || account.suspended? ? 'suspended' : 'active'
      end

      def time(value)
        value&.utc&.iso8601
      end
    end
  end
end
