# frozen_string_literal: true

module Inclamo
  module Shopify
    # Turns an order as the Admin API returns it into what the panel shows, and
    # says for each action whether this order allows it. Amounts stay strings
    # in the store's own notation; the dashboard formats them.
    class OrderPresenter
      def initialize(node, shop_domain:)
        @node = node
        @shop_domain = shop_domain
      end

      def as_json(*)
        {
          id: @node['id'], number: @node['name'], admin_url: admin_url, created_at: @node['createdAt'],
          cancelled_at: @node['cancelledAt'], cancel_reason: @node['cancelReason'],
          financial_status: @node['displayFinancialStatus'], fulfillment_status: @node['displayFulfillmentStatus'],
          return_status: @node['returnStatus'], currency: @node['currencyCode'],
          total: money('totalPriceSet'), refunded: money('totalRefundedSet'), shipping: money('totalShippingPriceSet'),
          refundable: { amount: refundable_amount.to_s('F'), currency: @node['currencyCode'] },
          items: items, shipments: shipments, refunds: refunds,
          customer: customer, shipping_address: shipping_address,
          actions: actions
        }
      end

      # Received minus refunded, never below zero.
      def refundable_amount
        received = BigDecimal(@node.dig('totalReceivedSet', 'shopMoney', 'amount') || '0')
        refunded = BigDecimal(@node.dig('totalRefundedSet', 'shopMoney', 'amount') || '0')
        [received - refunded, BigDecimal('0')].max
      end

      def cancelled?
        @node['cancelledAt'].present?
      end

      def shipped?
        Array(@node['fulfillments']).any? { |fulfillment| fulfillment['status'] != 'CANCELLED' }
      end

      # Why this order does not allow an action, or nil. Scopes and the role of
      # the agent are checked elsewhere; this is about the order itself.
      def refusal(action)
        case action.to_s
        when 'cancel' then 'already_cancelled' if cancelled?
        when 'refund' then 'nothing_to_refund' unless @node['refundable'] && refundable_amount.positive?
        when 'address'
          return 'already_cancelled' if cancelled?

          'already_shipped' if shipped?
        end
      end

      private

      def actions
        ShopifyConnection::ACTION_SCOPES.keys.index_with { |action| { allowed: refusal(action).nil?, reason: refusal(action) } }
      end

      def admin_url
        "https://admin.shopify.com/store/#{@shop_domain.delete_suffix('.myshopify.com')}/orders/#{@node['legacyResourceId']}"
      end

      def money(key)
        value = @node.dig(key, 'shopMoney')
        value && { amount: value['amount'], currency: value['currencyCode'] }
      end

      def items
        Array(@node.dig('lineItems', 'nodes')).map do |item|
          price = item.dig('discountedUnitPriceSet', 'shopMoney') || item.dig('originalUnitPriceSet', 'shopMoney') || {}
          {
            id: item['id'], title: item['title'], variant: item['variantTitle'], sku: item['sku'],
            quantity: item['quantity'], current_quantity: item['currentQuantity'],
            refundable_quantity: item['refundableQuantity'], unfulfilled_quantity: item['unfulfilledQuantity'],
            unit_price: { amount: price['amount'], currency: price['currencyCode'] }, image_url: item.dig('image', 'url')
          }
        end
      end

      def shipments
        Array(@node['fulfillments']).map do |fulfillment|
          {
            id: fulfillment['id'], status: fulfillment['displayStatus'] || fulfillment['status'], created_at: fulfillment['createdAt'],
            tracking: Array(fulfillment['trackingInfo']).map { |info| info.slice('company', 'number', 'url').symbolize_keys }
          }
        end
      end

      def refunds
        Array(@node['refunds']).map do |refund|
          value = refund.dig('totalRefundedSet', 'shopMoney') || {}
          { id: refund['id'], created_at: refund['createdAt'], note: refund['note'], amount: value['amount'], currency: value['currencyCode'] }
        end
      end

      def customer
        @node['customer'] && { id: @node.dig('customer', 'id'), name: @node.dig('customer', 'displayName') }
      end

      def shipping_address
        address = @node['shippingAddress']
        return unless address

        {
          name: address['name'], first_name: address['firstName'], last_name: address['lastName'], company: address['company'],
          address1: address['address1'], address2: address['address2'], city: address['city'],
          province: address['province'], province_code: address['provinceCode'], zip: address['zip'],
          country: address['country'], country_code: address['countryCodeV2'], phone: address['phone']
        }
      end
    end
  end
end
