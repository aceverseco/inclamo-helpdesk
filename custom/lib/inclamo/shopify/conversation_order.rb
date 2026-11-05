# frozen_string_literal: true

module Inclamo
  module Shopify
    # The one order a conversation is about. Its number, statuses, first
    # tracking number and links are kept as conversation attributes, so macros,
    # automation rules and other services can use them. The address and other
    # personal data are never written there.
    class ConversationOrder
      ID_KEY = 'shopify_order_id'
      # key => [label shown in Chatwoot, display type]
      DEFINITIONS = {
        'shopify_order_number' => ['Order number', :text],
        'shopify_order_payment_status' => ['Order payment status', :text],
        'shopify_order_fulfillment_status' => ['Order fulfilment status', :text],
        'shopify_order_tracking_number' => ['Order tracking number', :text],
        'shopify_order_tracking_link' => ['Order tracking link', :link],
        'shopify_order_admin_link' => ['Order in Shopify admin', :link]
      }.freeze
      NUMBER_IN_TEXT = /#?\b([A-Za-z]{0,4}-?\d{3,12})\b/
      MAX_CANDIDATES = 3

      # Makes the attributes known to Chatwoot for this account, so they can be
      # picked in macros, automation rules and the conversation sidebar.
      def self.ensure_definitions!(account)
        DEFINITIONS.each do |key, (label, type)|
          CustomAttributeDefinition.find_or_create_by!(account_id: account.id, attribute_model: :conversation_attribute, attribute_key: key) do |definition|
            definition.attribute_display_name = label
            definition.attribute_display_type = type
            definition.attribute_description = 'Set by Inclamo Helpdesk from the order this conversation is about.'
          end
        end
      end

      def self.attributes_for(node, shop_domain:)
        order = OrderPresenter.new(node, shop_domain: shop_domain).as_json
        tracking = order[:shipments].flat_map { |shipment| shipment[:tracking] }.first || {}
        {
          ID_KEY => order[:id],
          'shopify_order_number' => order[:number],
          'shopify_order_payment_status' => order[:financial_status].to_s.downcase,
          'shopify_order_fulfillment_status' => order[:fulfillment_status].to_s.downcase,
          'shopify_order_tracking_number' => tracking[:number],
          'shopify_order_tracking_link' => tracking[:url],
          'shopify_order_admin_link' => order[:admin_url]
        }.compact
      end

      def initialize(conversation)
        @conversation = conversation
        @record = ShopifyConnection.find_by(account_id: conversation.account_id)
      end

      def marked_id
        @conversation.custom_attributes.to_h[ID_KEY]
      end

      # Marks the order (as the Admin API returned it) and writes its attributes.
      # Also used to refresh them: nothing is written when nothing changed.
      def mark!(node)
        ours = [ID_KEY, *DEFINITIONS.keys]
        current = @conversation.custom_attributes.to_h
        updated = current.except(*ours).merge(self.class.attributes_for(node, shop_domain: @record.shop_domain))
        @conversation.update!(custom_attributes: updated) unless updated == current
        updated
      end

      def clear!
        current = @conversation.custom_attributes.to_h
        updated = current.except(ID_KEY, *DEFINITIONS.keys)
        @conversation.update!(custom_attributes: updated) unless updated == current
      end

      # Marks the order named in `text` when it belongs to the customer matched
      # for this conversation's contact. Returns the order, or nil.
      def auto_mark!(text)
        return if @record.nil? || !@record.working? || @record.customer_data_limited? || marked_id.present?

        candidates = text.to_s.scan(NUMBER_IN_TEXT).flatten.uniq.first(MAX_CANDIDATES)
        return if candidates.empty?

        reader = OrderReader.new(@record)
        match = CustomerMatcher.new(reader, @conversation.contact, limited: false).call
        return unless match.state == 'matched'

        candidates.each do |number|
          node = reader.order_by_number(number)
          next unless node && node.dig('customer', 'id') == match.customer_id

          mark!(node)
          return node
        end
        nil
      end
    end
  end
end
