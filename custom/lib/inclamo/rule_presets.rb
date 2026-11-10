# frozen_string_literal: true

module Inclamo
  # The ready automation rules an administrator switches on with one toggle.
  # Switching one on creates an ordinary Chatwoot automation rule, to be read
  # and edited in Chatwoot's own list like any other. The overlay keeps no
  # table of them: a rule is recognised by the last line of its description.
  # Switching off deactivates the rule and changes nothing else in it.
  class RulePresets
    MARKER = 'inclamo-preset:'
    EVENT = 'conversation_created'
    # key => the labels its rule adds, and the fact its value is compared with
    PRESETS = {
      'vip' => { labels: %w[vip], value_fact: 'shopify_customer_spent' },
      'not_shipped' => { labels: %w[awaiting-shipment] },
      'no_orders' => { labels: %w[pre-sale] }
    }.freeze

    class ValueRequired < StandardError; end

    def self.known?(key)
      PRESETS.key?(key.to_s)
    end

    def initialize(account)
      @account = account
    end

    def as_json(*)
      record = ShopifyConnection.find_by(account_id: @account.id)
      {
        store_connected: record&.working? || false, currency: record&.shop_currency,
        presets: PRESETS.keys.map { |key| present(key) }
      }
    end

    # Creates the preset's rule, or activates the one it created earlier. A
    # value replaces the one in the rule's own condition and nothing else.
    def switch_on!(key, value: nil)
      preset = PRESETS.fetch(key)
      amount = amount_from(value) if preset[:value_fact]
      Shopify::CustomerFacts.ensure_definitions!(@account)
      # A rule's "add label" needs the label to exist.
      preset[:labels].each { |title| @account.labels.find_or_create_by!(title: title) }

      rule = rule_of(key)
      return create_rule(key, amount) unless rule

      rule.conditions = with_value(rule.conditions, preset[:value_fact], amount) if amount
      rule.active = true
      rule.save!
      rule
    end

    def switch_off!(key)
      PRESETS.fetch(key)
      # Not `update!`: a rule the administrator's later changes made invalid
      # can still be switched off.
      rule_of(key)&.update_attribute(:active, false) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def present(key)
      rule = rule_of(key)
      fact = PRESETS[key][:value_fact]
      {
        key: key, name: text(key, :name), about: text(key, :about), needs_value: fact.present?,
        on: rule&.active? || false, rule_id: rule&.id, rule_name: rule&.name,
        value: rule && fact ? value_in(rule.conditions, fact) : nil
      }
    end

    def rule_of(key)
      marker = "#{MARKER} #{key}"
      @account.automation_rules.where('description LIKE ?', "%#{marker}%").order(:id)
              .find { |rule| rule.description.to_s.strip.lines.last.to_s.strip == marker }
    end

    def create_rule(key, amount)
      @account.automation_rules.create!(
        name: text(key, :name), description: "#{text(key, :about)}\n#{MARKER} #{key}",
        event_name: EVENT, active: true, conditions: conditions_of(key, amount), actions: actions_of(key)
      )
    end

    def conditions_of(key, amount)
      case key
      when 'vip' then [fact('shopify_customer_spent', 'is_greater_than', amount)]
      when 'not_shipped' then [fact('shopify_last_order_fulfillment_status', 'equal_to', 'unfulfilled')]
      # Unknown to the store, or known to it without an order yet.
      when 'no_orders' then [fact('shopify_is_customer', 'equal_to', 'no', 'OR'), fact('shopify_customer_orders', 'is_less_than', '1')]
      end
    end

    def actions_of(key)
      labels = { 'action_name' => 'add_label', 'action_params' => PRESETS[key][:labels] }
      key == 'vip' ? [{ 'action_name' => 'change_priority', 'action_params' => ['high'] }, labels] : [labels]
    end

    def fact(key, operator, value, joined_by = nil)
      { 'attribute_key' => key, 'filter_operator' => operator, 'values' => [value], 'query_operator' => joined_by,
        'custom_attribute_type' => 'conversation_attribute' }
    end

    def value_in(conditions, fact)
      Array(conditions.find { |condition| condition['attribute_key'] == fact }&.dig('values')).first
    end

    def with_value(conditions, fact, amount)
      conditions.map { |condition| condition['attribute_key'] == fact ? condition.merge('values' => [amount]) : condition }
    end

    # The amount as the rule keeps it: "500", "499.5".
    def amount_from(value)
      amount = BigDecimal(value.to_s.strip)
      raise ValueRequired unless amount.finite? && !amount.negative?

      amount.frac.zero? ? amount.to_i.to_s : amount.to_s('F')
    rescue ArgumentError
      raise ValueRequired
    end

    def text(key, name)
      I18n.t("inclamo.rule_presets.#{key}.#{name}")
    end
  end
end
