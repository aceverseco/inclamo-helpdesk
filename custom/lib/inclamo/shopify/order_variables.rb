# frozen_string_literal: true

module Inclamo
  module Shopify
    # One order as a reply states it: the values of the reply variables
    # `order.*`, computed from the order as the Admin API returns it. The one
    # place for both sides: the message drop renders them on the server, and
    # the panel hands the same values to the dashboard's editor.
    class OrderVariables
      NAMES = %w[number date total payment_status fulfillment_status tracking_number tracking_link status_link items].freeze
      # Currencies written without decimal places, or with three (ISO 4217).
      NO_DECIMALS = %w[BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX UYI VND VUV XAF XOF XPF].freeze
      THREE_DECIMALS = %w[BHD IQD JOD KWD LYD OMR TND].freeze

      def initialize(node)
        @node = node
      end

      # Every variable by its name; a fact the order does not have is ''.
      def to_h
        NAMES.index_with { |name| public_send(name).to_s }
      end

      def number
        @node['name']
      end

      # The day the order was placed, in UTC: "November 5, 2026".
      def date
        Time.iso8601(@node['createdAt'].to_s).utc.strftime('%B %-d, %Y')
      rescue ArgumentError
        nil
      end

      # The order total with its currency: "1,585.90 UAH".
      def total
        money = @node.dig('totalPriceSet', 'shopMoney')
        return unless money && money['amount'].present?

        currency = money['currencyCode'].to_s
        ActiveSupport::NumberHelper.number_to_currency(
          BigDecimal(money['amount'].to_s), unit: currency, format: '%n %u', precision: decimals(currency), locale: :en
        ).strip
      rescue ArgumentError
        nil
      end

      def payment_status
        StatusWords.for(@node['displayFinancialStatus'])
      end

      def fulfillment_status
        StatusWords.for(@node['displayFulfillmentStatus'])
      end

      def tracking_number
        tracking['number']
      end

      def tracking_link
        tracking['url']
      end

      # The order status page the store shows the customer.
      def status_link
        @node['statusPageUrl']
      end

      # One line per item: "2 × Blue Mug".
      def items
        Array(@node.dig('lineItems', 'nodes')).map { |item| "#{item['quantity']} × #{item['title']}" }.join("\n")
      end

      private

      # The first tracking entry of the order's shipments: the one the
      # conversation attributes carry as well.
      def tracking
        Array(@node['fulfillments']).flat_map { |fulfillment| Array(fulfillment['trackingInfo']) }.first || {}
      end

      def decimals(currency)
        return 0 if NO_DECIMALS.include?(currency)

        THREE_DECIMALS.include?(currency) ? 3 : 2
      end
    end
  end
end
