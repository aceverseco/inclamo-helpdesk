# frozen_string_literal: true

# The preset automation rules of the account: which exist, which are on.
# Only administrators see and switch them.
class Api::V1::Accounts::Inclamo::RulePresetsController < Api::V1::Accounts::BaseController
  before_action :require_administrator

  def index
    render json: presets
  end

  # Switches the preset params[:id] on (`active: true`, with `value` where the
  # preset needs one) or off (`active: false`).
  def update
    key = params[:id].to_s
    return head :not_found unless ::Inclamo::RulePresets.known?(key)

    if ActiveModel::Type::Boolean.new.cast(params[:active])
      presets.switch_on!(key, value: params[:value])
    else
      presets.switch_off!(key)
    end
    render json: presets
  rescue ::Inclamo::RulePresets::ValueRequired
    refuse(:value_required)
  rescue ActiveRecord::RecordInvalid
    refuse(:rule_invalid)
  end

  private

  def presets
    @presets ||= ::Inclamo::RulePresets.new(Current.account)
  end

  def require_administrator
    refuse(:forbidden, :forbidden) unless Current.account_user&.administrator?
  end

  def refuse(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("inclamo.rule_presets.errors.#{code}") }, status: status
  end
end
