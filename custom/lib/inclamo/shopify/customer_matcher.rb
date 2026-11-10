# frozen_string_literal: true

module Inclamo
  module Shopify
    # Finds the store's customer for a contact: by a choice an agent made
    # earlier, else by email, else by phone. One exact match is used; several
    # are offered to the agent; nothing is ever guessed.
    class CustomerMatcher
      REMEMBERED = 'inclamo_shopify_customer_id'
      # `customer` is the store's answer for the one customer found by a search;
      # nil for a customer an agent chose earlier, who is not searched for.
      Result = Struct.new(:state, :customer_id, :candidates, :customer, keyword_init: true)

      def initialize(reader, contact, limited:)
        @reader = reader
        @contact = contact
        @limited = limited
      end

      def call
        return Result.new(state: 'limited', candidates: []) if @limited

        remembered = @contact.custom_attributes.to_h[REMEMBERED]
        return Result.new(state: 'matched', customer_id: remembered, candidates: []) if remembered.present?
        return Result.new(state: 'no_identifier', candidates: []) if @contact.email.blank? && @contact.phone_number.blank?

        found = @contact.email.present? ? @reader.customers_by_email(@contact.email) : []
        found = @reader.customers_by_phone(@contact.phone_number) if found.empty? && @contact.phone_number.present?
        result_for(found)
      end

      def self.remember!(contact, customer_id)
        attributes = contact.custom_attributes.to_h
        customer_id.present? ? attributes[REMEMBERED] = customer_id : attributes.delete(REMEMBERED)
        contact.update!(custom_attributes: attributes)
      end

      def self.candidate(node)
        {
          id: node['id'], name: node['displayName'], email: node.dig('defaultEmailAddress', 'emailAddress'),
          phone: node.dig('defaultPhoneNumber', 'phoneNumber'), orders_count: node['numberOfOrders'].to_i,
          total_spent: node['amountSpent'] && { amount: node.dig('amountSpent', 'amount'), currency: node.dig('amountSpent', 'currencyCode') }
        }
      end

      private

      def result_for(found)
        case found.size
        when 0 then Result.new(state: 'none', candidates: [])
        when 1 then Result.new(state: 'matched', customer_id: found.first['id'], candidates: [], customer: found.first)
        else Result.new(state: 'ambiguous', candidates: found.map { |node| self.class.candidate(node) })
        end
      end
    end
  end
end
