# frozen_string_literal: true

# Connects an account the store app has just created or restored to its store
# through the app (Inclamo::Shopify::AppConnection). When the app gives no key
# or the key does not do, the account stays without a connection and an
# administrator can ask again from the connection page; nothing is retried
# here, so the app is not asked over and over for a store it cannot serve.
class Inclamo::StoreAccessJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account&.active?

    Inclamo::Shopify::AppConnection.connect!(account)
  rescue Inclamo::Shopify::Error => e
    # The class only: a message may echo what the store or the app said.
    Rails.logger.info("[inclamo store key] account #{account_id} is not connected through the store app: #{e.class.name.demodulize}")
  end
end
