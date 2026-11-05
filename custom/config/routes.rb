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
          resources :order_roles, only: [:index, :create, :destroy]
          namespace :shopify do
            resource :connection, only: [:show, :create, :destroy], controller: '/api/v1/accounts/inclamo/shopify_connections' do
              post :recheck
            end
            scope 'conversations/:conversation_id', controller: '/api/v1/accounts/inclamo/conversation_panels' do
              get 'panel', action: :show
              get 'lookup', action: :lookup
              post 'customer', action: :choose_customer
              delete 'customer', action: :forget_customer
              put 'order', action: :mark_order
              delete 'order', action: :clear_order
            end
            scope 'conversations/:conversation_id' do
              post 'actions/refund_preview', to: '/api/v1/accounts/inclamo/order_actions#refund_preview'
              resources :actions, only: [:create, :show], controller: '/api/v1/accounts/inclamo/order_actions'
            end
          end
        end
      end
    end
  end
end
