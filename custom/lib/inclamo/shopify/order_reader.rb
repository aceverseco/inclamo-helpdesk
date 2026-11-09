# frozen_string_literal: true

module Inclamo
  module Shopify
    # Reads customers and orders of an account's store. Answers are reused for
    # at most a minute and are never written to the database. After an order
    # action, `forget!` makes every earlier answer of the account unreachable.
    class OrderReader
      CACHE_FOR = 60 # seconds
      PAGE = 10
      NUMBER_FORMAT = /\A[A-Za-z0-9_.-]{1,40}\z/
      ORDER_ID = %r{\Agid://shopify/Order/\d+\z}
      CUSTOMER_ID = %r{\Agid://shopify/Customer/\d+\z}

      def initialize(record, time_limit: nil)
        @record = record
        @store = StoreConnection.new(record, time_limit: time_limit)
      end

      def self.forget!(account_id)
        ::Redis::Alfred.incr(generation_key(account_id))
      end

      def self.generation_key(account_id)
        "inclamo:shopify:#{account_id}:generation"
      end

      # Customers whose email or phone is exactly the one given.
      def customers_by_email(email)
        search("email:#{quote(email)}").select { |node| node.dig('defaultEmailAddress', 'emailAddress').to_s.casecmp?(email) }
      end

      def customers_by_phone(phone)
        digits = phone.to_s.gsub(/\D/, '')
        search("phone:#{quote(phone)}").select { |node| node.dig('defaultPhoneNumber', 'phoneNumber').to_s.gsub(/\D/, '') == digits }
      end

      # The customer with one page of orders, newest first; nil when the id is unknown.
      def customer_with_orders(customer_id, after: nil)
        return unless customer_id.to_s.match?(CUSTOMER_ID)

        cached("customer:#{customer_id}:#{after}") do
          @store.query(:customer_orders, { id: customer_id, first: PAGE, after: after })['customer']
        end
      end

      def order(order_id)
        return unless order_id.to_s.match?(ORDER_ID)

        document = limited? ? :order_details_limited : :order_details
        cached("order:#{order_id}") { @store.query(document, { id: order_id })['order'] }
      end

      # The tags and note of an order or a customer as the store holds them
      # now: never from the cache, so that a note is edited from what the store
      # has, and a customer is known to exist before it is changed.
      def order_marks(order_id)
        return unless order_id.to_s.match?(ORDER_ID)

        @store.query(:order_marks, { id: order_id })['order']
      end

      def customer_marks(customer_id)
        return if limited? || !customer_id.to_s.match?(CUSTOMER_ID)

        @store.query(:customer_marks, { id: customer_id })['customer']
      end

      # The order with exactly this number, or nil. "#1042" and "1042" are the same.
      def order_by_number(number)
        wanted = number.to_s.strip.delete_prefix('#')
        return unless wanted.match?(NUMBER_FORMAT)

        document = limited? ? :orders_by_number_limited : :orders_by_number
        nodes = cached("number:#{wanted.downcase}") { @store.query(document, { query: "name:#{quote(wanted)}" }).dig('orders', 'nodes') }
        Array(nodes).find { |node| node['name'].to_s.delete_prefix('#').casecmp?(wanted) }
      end

      private

      def limited?
        @record.customer_data_limited?
      end

      def search(query)
        return [] if limited?

        Array(cached("search:#{query}") { @store.query(:customers_search, { query: query }).dig('customers', 'nodes') })
      end

      # A search term as one quoted phrase, so it cannot add terms of its own.
      def quote(value)
        %("#{value.to_s.gsub(/["\\]/, '')}")
      end

      def cached(suffix)
        generation = ::Redis::Alfred.get(self.class.generation_key(@record.account_id)).to_i
        key = "inclamo:shopify:#{@record.account_id}:#{generation}:#{Digest::SHA256.hexdigest(suffix)}"
        hit = ::Redis::Alfred.get(key)
        return JSON.parse(hit)['value'] if hit

        value = yield
        ::Redis::Alfred.setex(key, { value: value }.to_json, CACHE_FOR)
        value
      end
    end
  end
end
