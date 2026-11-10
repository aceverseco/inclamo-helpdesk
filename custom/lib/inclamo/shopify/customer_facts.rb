# frozen_string_literal: true

module Inclamo
  module Shopify
    # What the store knows about the customer behind a conversation, kept as
    # conversation attributes with definitions, so that Chatwoot's own
    # automation rules can use them as conditions. Counts, amounts, statuses
    # and tags only: no name, email, phone or address is ever written here.
    class CustomerFacts
      IS_CUSTOMER = 'shopify_is_customer'
      # key => [label shown in Chatwoot, display type, values of a list]
      DEFINITIONS = {
        IS_CUSTOMER => ['Is a customer of the store', :list, %w[yes no]],
        'shopify_customer_orders' => ["Customer's number of orders", :number],
        'shopify_customer_spent' => ["Customer's total spent", :number],
        'shopify_customer_tags' => ["Customer's tags", :text],
        'shopify_last_order_payment_status' => ["Latest order's payment status", :text],
        'shopify_last_order_fulfillment_status' => ["Latest order's fulfilment status", :text],
        'shopify_last_order_total' => ["Latest order's total", :number],
        'shopify_last_order_tags' => ["Latest order's tags", :text]
      }.freeze
      KEYS = DEFINITIONS.keys.freeze
      NOT_A_CUSTOMER = { IS_CUSTOMER => 'no' }.freeze
      # Chatwoot refuses a text attribute longer than this.
      TEXT_LIMIT = 1500

      # Makes the facts known to Chatwoot for this account, so the automation
      # rule editor offers them as conditions. One query when they all exist.
      def self.ensure_definitions!(account)
        scope = CustomAttributeDefinition.where(account_id: account.id, attribute_model: :conversation_attribute)
        return if scope.where(attribute_key: KEYS).count == KEYS.size

        DEFINITIONS.each do |key, (label, type, values)|
          CustomAttributeDefinition.find_or_create_by!(account_id: account.id, attribute_model: :conversation_attribute, attribute_key: key) do |definition|
            definition.attribute_display_name = label
            definition.attribute_display_type = type
            definition.attribute_values = values if values
            definition.attribute_description = 'Set by Inclamo Helpdesk from the store, for automation rules.'
          end
        end
      end

      # The facts of a customer as the Admin API returns one (CustomerFactFields).
      # Amounts are numbers in the store's currency; tags are one text, comma-separated.
      def self.of(customer)
        latest = Array(customer.dig('latestOrders', 'nodes')).first
        facts = {
          IS_CUSTOMER => 'yes',
          'shopify_customer_orders' => customer['numberOfOrders'].to_i,
          'shopify_customer_spent' => number(customer.dig('amountSpent', 'amount')),
          'shopify_customer_tags' => tags(customer['tags'])
        }
        if latest
          facts.merge!(
            'shopify_last_order_payment_status' => latest['displayFinancialStatus'].to_s.downcase,
            'shopify_last_order_fulfillment_status' => latest['displayFulfillmentStatus'].to_s.downcase,
            'shopify_last_order_total' => number(latest.dig('totalPriceSet', 'shopMoney', 'amount')),
            'shopify_last_order_tags' => tags(latest['tags'])
          )
        end
        facts.compact
      end

      def self.number(amount)
        value = BigDecimal(amount.to_s)
        value.frac.zero? ? value.to_i : value.to_f
      rescue ArgumentError
        nil
      end
      private_class_method :number

      # As many whole tags as a text attribute holds.
      def self.tags(list)
        Array(list).each_with_object(+'') do |tag, text|
          more = text.empty? ? tag.to_s : "#{text}, #{tag}"
          break text if more.length > TEXT_LIMIT

          text.replace(more)
        end
      end
      private_class_method :tags

      def initialize(conversation, connection: nil)
        @conversation = conversation
        @record = connection || ShopifyConnection.find_by(account_id: conversation.account_id)
      end

      # Reads the facts from the store and writes them; returns what was read,
      # or nil when the account has no working store. A store that does not
      # answer raises Inclamo::Shopify::Error and nothing is written. `reader`
      # is an OrderReader or anything that reads like one.
      def refresh!(reader: nil, quiet: false)
        return unless @record&.working?

        write!(read(reader || OrderReader.new(@record)), quiet: quiet)
      end

      # Replaces the facts of the conversation with the given ones and leaves
      # its other attributes alone. Nothing is written when nothing changed.
      # See ConversationAttributes for what a quiet write is.
      def write!(facts, quiet: false)
        self.class.ensure_definitions!(@conversation.account) if facts.present?
        ConversationAttributes.replace!(@conversation, KEYS, facts, quiet: quiet)
        facts
      end

      private

      # One customer: their facts. Nobody: "not a customer" and nothing else.
      # Several customers, or a store that hides customer data: nothing at all,
      # because nothing is ever guessed.
      def read(reader)
        return {} if @record.customer_data_limited?

        match = CustomerMatcher.new(reader, @conversation.contact, limited: false).call
        case match.state
        when 'matched'
          # A customer an agent chose earlier is not searched for: read by id.
          customer = match.customer || reader.customer_with_orders(match.customer_id)
          customer ? self.class.of(customer) : NOT_A_CUSTOMER
        when 'none', 'no_identifier' then NOT_A_CUSTOMER
        else {}
        end
      end
    end
  end
end
