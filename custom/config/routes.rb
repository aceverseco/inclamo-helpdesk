# frozen_string_literal: true

# Routes of the overlay. Evaluated inside Chatwoot's route set, before its own
# routes (see custom/config/overlay.rb). Everything lives under
# /api/v1/accounts/:account_id/inclamo/.

namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :inclamo do
          resource :status, only: [:show], controller: 'status'
          namespace :shopify do
            resource :connection, only: [:show, :create, :destroy], controller: '/api/v1/accounts/inclamo/shopify_connections' do
              post :recheck
            end
          end
        end
      end
    end
  end
end
