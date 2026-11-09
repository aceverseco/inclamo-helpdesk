# frozen_string_literal: true

module Inclamo
  module Shopify
    # The words for an order's payment and fulfilment status. One table
    # (`inclamo.order_statuses` in the overlay's locale file) for the panel and
    # for the reply variables, so the two cannot drift. English for now.
    module StatusWords
      # "PARTIALLY_FULFILLED" => "Partially shipped". A status the table does
      # not know is shown as plain words: "SOMETHING_NEW" => "Something new".
      def self.for(status)
        key = status.to_s.strip.upcase
        return '' if key.empty?

        I18n.t(key, scope: 'inclamo.order_statuses', locale: :en, default: key.downcase.tr('_', ' ').upcase_first)
      end
    end
  end
end
