# frozen_string_literal: true

require Rails.root.join('custom/spec/support/provisioning_requests')

# Plays the store app's erasure request (docs/app-store-erasure.md §3) in
# request specs, and runs the daily erasure run with its background jobs.
module ErasureRequests
  def ask_erasure(domain = ProvisioningRequests::STORE, body: { contract: 1 }, **)
    provisioning_call(:post, domain, body: body, suffix: '/erasure', **)
  end

  # A store whose account the app provisioned and then removed.
  def suspended_store(domain = ProvisioningRequests::STORE, **)
    provision(domain, **)
    remove_app(domain)
    provisioned(domain)
  end

  # The daily run at the current time, with every background job it starts
  # (Chatwoot's deletion included) performed before it returns.
  def run_erasures
    perform_enqueued_jobs { Inclamo::ErasureCheckJob.perform_now }
  end

  def store_record(domain = ProvisioningRequests::STORE)
    Inclamo::ErasureRequest.stores.where(shop_domain: domain).order(:id).last
  end

  def events_of(domain = ProvisioningRequests::STORE)
    Inclamo::ProvisioningEvent.where(shop_domain: domain).order(:id).pluck(:outcome)
  end
end
