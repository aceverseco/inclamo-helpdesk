# frozen_string_literal: true

# The account's Shopify store connection. Every member may read what is
# connected; only administrators connect, check again and remove. No answer of
# this controller carries the client secret or a token.
class Api::V1::Accounts::Inclamo::ShopifyConnectionsController < Api::V1::Accounts::BaseController
  before_action :require_administrator, except: [:show]

  ERROR_STATUS = {
    forbidden: :forbidden,
    not_connected: :not_found,
    store_unreachable: :bad_gateway
  }.freeze

  def show
    render json: present(connection)
  end

  def create
    return refuse(:encryption_not_configured) unless Chatwoot.encryption_configured?

    domain = ::Inclamo::Shopify::Verifier.normalize_domain(params[:shop_domain])
    existing = connection
    return refuse(:already_connected) if existing && existing.shop_domain != domain

    result = ::Inclamo::Shopify::Verifier.call(domain: domain, **submitted_credentials)
    record = existing || ::Inclamo::ShopifyConnection.new(account: Current.account)
    record.update!(attributes_from(result))
    ::Inclamo::Shopify::ConversationOrder.ensure_definitions!(Current.account)
    render json: present(record), status: existing ? :ok : :created
  rescue ::Inclamo::Shopify::Error => e
    refuse_for(e)
  end

  def recheck
    return refuse(:not_connected) unless connection

    ::Inclamo::Shopify::StoreConnection.new(connection).recheck!
    render json: present(connection)
  rescue ::Inclamo::Shopify::Error => e
    refuse_for(e)
  end

  def destroy
    connection&.destroy!
    head :no_content
  end

  private

  def connection
    @connection ||= ::Inclamo::ShopifyConnection.find_by(account_id: Current.account.id)
  end

  def require_administrator
    refuse(:forbidden) unless Current.account_user&.administrator?
  end

  def submitted_credentials
    if params[:access_token].present?
      { access_token: params[:access_token].to_s.strip }
    else
      { client_id: params[:client_id].to_s.strip, client_secret: params[:client_secret].to_s.strip }
    end
  end

  def attributes_from(result)
    legacy = params[:access_token].present?
    {
      shop_domain: result.shop_domain, shop_name: result.shop_name, shop_currency: result.shop_currency,
      auth_kind: legacy ? 'legacy_token' : 'client_credentials',
      client_id: legacy ? nil : params[:client_id].to_s.strip,
      client_secret: legacy ? nil : params[:client_secret].to_s.strip,
      access_token: result.access_token, token_expires_at: result.token_expires_at,
      scopes: result.scopes, customer_data_mode: result.customer_data_mode,
      api_version: ::Inclamo::Shopify::API_VERSION, status: 'working', last_checked_at: Time.current
    }
  end

  def present(record)
    return { connected: false, encryption_configured: Chatwoot.encryption_configured?, viewer: viewer } unless record

    {
      viewer: viewer,
      connected: true, status: record.status, shop_name: record.shop_name, shop_domain: record.shop_domain,
      shop_currency: record.shop_currency, auth_kind: record.auth_kind, customer_data: record.customer_data_mode,
      scopes: record.scopes, actions: record.actions_report, api_version: record.api_version,
      last_checked_at: record.last_checked_at
    }
  end

  # What the signed-in member may do; the dashboard shows or hides by it, the
  # server checks again on every request.
  def viewer
    { administrator: Current.account_user&.administrator? || false, can_act_on_orders: ::Inclamo::OrderRole.allows?(Current.account_user) }
  end

  def refuse_for(error)
    case error
    when ::Inclamo::Shopify::Error::InvalidDomain then refuse(:invalid_domain)
    when ::Inclamo::Shopify::Error::AppNotInstalled then refuse(:app_not_installed)
    when ::Inclamo::Shopify::Error::Unauthorized then refuse(:credentials_refused)
    when ::Inclamo::Shopify::Error::MissingScopes then refuse(:missing_scopes, missing_scopes: error.scopes)
    when ::Inclamo::Shopify::Error::OrdersRefused then refuse(:orders_refused)
    when ::Inclamo::Shopify::Error::ShopUnavailable then refuse(:shop_unavailable)
    else refuse(:store_unreachable)
    end
  end

  def refuse(code, extra = {})
    message = I18n.t("inclamo.shopify_connection.errors.#{code}", **extra.transform_values { |value| Array(value).join(', ') })
    render json: { error: code, message: message }.merge(extra), status: ERROR_STATUS.fetch(code, :unprocessable_entity)
  end
end
