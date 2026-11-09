# frozen_string_literal: true

module Inclamo
  # The common staff authorization contract. Always read current membership
  # and grants: a loaded object must not outlive a revocation or demotion.
  module ActionPermissions
    ACTIONS = %w[address edit_items cancel refund new_order replacement discount order_tags order_note customer_tags customer_note].freeze
    ORDER_ACTIONS = (ACTIONS - ['discount']).freeze

    def self.current_member(member)
      AccountUser.find_by(id: member.id, account_id: member.account_id, user_id: member.user_id) if member&.persisted?
    end

    def self.for(member)
      current = current_member(member)
      return ACTIONS.index_with { false } unless current
      return ACTIONS.index_with { true } if current.administrator?

      actions = Array(OrderRole.find_by(account_user_id: current.id)&.permissions)
      discount = DiscountGrant.exists?(account_user_id: current.id)
      ACTIONS.index_with { |action| action == 'discount' ? discount : actions.include?(action) }
    end

    def self.required(action, params = {})
      action = action.to_s
      values = params.to_h.stringify_keys
      rights = [action]
      rights << 'refund' if action == 'cancel' && values['refund'] == true
      rights << 'discount' if action == 'new_order' && values['discount'].present?
      rights
    end

    def self.allows?(member, action, params = {})
      granted = self.for(member)
      required(action, params).all? { |right| granted[right] == true }
    end

    def self.set!(member, action, enabled, by:)
      raise ArgumentError, 'invalid_permission' unless ACTIONS.include?(action) && [true, false].include?(enabled)

      member.with_lock do
        return if member.administrator?

        if action == 'discount'
          scope = DiscountGrant.where(account_user_id: member.id)
          enabled ? scope.first_or_create!(granted_by: by) : scope.destroy_all
        else
          grant = OrderRole.find_or_initialize_by(account_user_id: member.id)
          actions = grant.persisted? ? grant.permissions : []
          grant.permissions = enabled ? (actions | [action]) : (actions - [action])
          grant.granted_by = by
          grant.save!
        end
      end
    end
  end
end
