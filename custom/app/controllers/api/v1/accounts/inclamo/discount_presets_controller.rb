# frozen_string_literal: true

# The discount presets of the account: what agents may give. Administrators
# keep them; a member who holds the right to give discounts may read them.
class Api::V1::Accounts::Inclamo::DiscountPresetsController < Api::V1::Accounts::BaseController
  before_action :require_administrator, except: :index
  before_action :require_right, only: :index

  def index
    render json: { presets: presets }
  end

  def create
    preset = ::Inclamo::DiscountPreset.new(preset_params.merge(account_id: Current.account.id))
    save(preset, :created)
  end

  def update
    preset = find_preset
    return head :not_found unless preset

    preset.assign_attributes(preset_params)
    save(preset, :ok)
  end

  def destroy
    preset = find_preset
    return head :not_found unless preset

    preset.destroy!
    render json: { presets: presets }
  end

  private

  # A refused preset names each field and why, for the form to show.
  def save(preset, status)
    if preset.save
      render json: { preset: preset, presets: presets }, status: status
    else
      fields = preset.errors.details.transform_values { |list| list.map { |detail| detail[:error].to_s } }
      render json: { error: 'invalid', fields: fields }, status: :unprocessable_entity
    end
  end

  def preset_params
    params.slice(*::Inclamo::DiscountPreset::FIELDS).permit(*::Inclamo::DiscountPreset::FIELDS).to_h
  end

  def find_preset
    ::Inclamo::DiscountPreset.find_by(account_id: Current.account.id, id: params[:id])
  end

  def presets
    ::Inclamo::DiscountPreset.where(account_id: Current.account.id).ordered.map(&:as_json)
  end

  def require_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden', message: I18n.t('inclamo.discounts.errors.forbidden') }, status: :forbidden
  end

  def require_right
    return if ::Inclamo::DiscountGrant.allows?(Current.account_user)

    render json: { error: 'forbidden', message: I18n.t('inclamo.discounts.errors.not_allowed') }, status: :forbidden
  end
end
