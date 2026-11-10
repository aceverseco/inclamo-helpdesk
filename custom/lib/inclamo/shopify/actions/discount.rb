# frozen_string_literal: true

module Inclamo
  module Shopify
    module Actions
      # Creates a discount code from a preset an administrator set, for the
      # agent to put into the reply. It is not about an existing order.
      #
      # The agent sends only the preset. The conditions are copied from it into
      # the record when the action starts, with the code's text, before the
      # store is asked: changing the preset later changes no code, and a lost
      # answer is settled by looking the text up at the store.
      #
      # The store refuses a text it already has (TAKEN), whatever its case, so
      # a code is never made twice. A taken text is replaced and tried again,
      # ATTEMPTS in all. Only the request that started the action creates;
      # settling an earlier attempt only looks the code up (after LOOK_AFTER).
      class Discount < Base
        RECORDED = %w[preset_id].freeze
        PREFIX = 'THANKS-'
        # No look-alike characters: no I, O, 0 or 1.
        ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.chars.freeze
        LENGTH = 8
        ATTEMPTS = 3
        LOOK_AFTER = 30.seconds
        # What the dialog gets back to insert.
        RESULT = %w[code discount_id].freeze

        def self.code_text
          PREFIX + Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
        end

        def self.context(connection:, extra:)
          { customer: extra[:customer], starting: extra.key?(:customer) }
        end

        def initialize(customer: nil, starting: false, **rest)
          super(order: nil, **rest.except(:order))
          @customer = customer
          @starting = starting
        end

        # Why no code can be made from this preset here, decided before the store is asked.
        def refusal
          preset = self.preset
          return 'unknown_preset' unless preset
          return 'customer_not_found' if preset.audience == 'customer' && @customer.nil?

          nil
        end

        def call
          return :accepted if @record.progress['discount_id']

          if @starting
            prepare! unless params['code']
            create!
          else
            return :unknown if @record.created_at.present? && @record.created_at > LOOK_AFTER.ago

            find_lost_code or raise Refused, 'not_created'
          end
          :accepted
        end

        private

        def preset
          @preset ||= DiscountPreset.find_by(account_id: @record.account_id, id: params['preset_id'].to_s.presence)
        end

        # The preset's conditions as they are now, and the code's text.
        def prepare!
          refused = refusal
          raise Refused, refused if refused

          expires_at = (Time.current + preset.expires_in_days.days).utc.iso8601 if preset.expires_in_days
          @record.update!(params: params.merge(
            'preset_name' => preset.name, 'kind' => preset.kind, 'value' => preset.as_json[:value],
            'usage_limit' => preset.usage_limit, 'audience' => preset.audience, 'expires_at' => expires_at,
            'customer_id' => (@customer['id'] if preset.audience == 'customer'), 'code' => self.class.code_text
          ).compact)
        end

        def create!
          ATTEMPTS.times do |attempt|
            remember!(attempted: true)
            answer = @store.query(:discount_code_create, { input: input })['discountCodeBasicCreate']
            node = answer['codeDiscountNode']
            return remember!(discount_id: node['id'], code: params['code']) if node

            errors = Array(answer['userErrors'])
            raise Refused, 'store_refused' if errors.empty?

            user_errors!(errors) unless taken?(errors) && attempt < ATTEMPTS - 1
            @record.update!(params: params.merge('code' => self.class.code_text))
          end
          raise Refused, 'store_refused'
        end

        def taken?(errors)
          errors.any? && errors.all? { |error| error['code'] == 'TAKEN' && Array(error['field']).last == 'code' }
        end

        # After a lost answer: did the store make the code anyway?
        def find_lost_code
          return unless @record.progress['attempted'] && params['code']

          node = @store.query(:discount_code_by_code, { code: params['code'] })['codeDiscountNodeByCode']
          return unless node && node.dig('codeDiscount', 'title') == title

          remember!(discount_id: node['id'], code: params['code'])
        end

        def title
          "#{params['preset_name']} · helpdesk conversation #{@record.conversation&.display_id}"
        end

        def input
          value = if params['kind'] == 'percentage'
                    { percentage: (params['value'].to_d / 100).to_f }
                  else
                    { discountAmount: { amount: params['value'].to_s, appliesOnEachItem: false } }
                  end
          customer = params['audience'] == 'customer'
          {
            title: title, code: params['code'], startsAt: Time.current.utc.iso8601, endsAt: params['expires_at'],
            usageLimit: params['usage_limit'].to_i,
            # A code for one customer may be used all its times by them; a code for anyone, once by each buyer.
            appliesOncePerCustomer: !customer,
            context: customer ? { customers: { add: [params['customer_id']] } } : { all: 'ALL' },
            customerGets: { value: value, items: { all: true } }
          }
        end
      end
    end
  end
end
