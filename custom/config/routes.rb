# frozen_string_literal: true

# Routes of the overlay. Evaluated inside Chatwoot's route set, before its own
# routes (see custom/config/overlay.rb). Everything lives under
# /api/v1/accounts/:account_id/inclamo/.

# Signed delivery of validated website-widget images.
get '/inclamo/widget-images/:id', to: 'inclamo/widget_images#show'

scope '/inclamo/support/v1', controller: 'inclamo/support/intake', defaults: { format: 'json' } do
  post 'register', action: :register
  post 'submissions', action: :submit
  post 'uploads', action: :upload
  get 'events', action: :sync
  post 'requests/:id/reconcile', action: :reconcile
  get 'requests/:id/attachments/:file_id', action: :attachment
  post 'recipients', action: :recipients
  post 'recipients/verify', action: :verify_recipient
end

namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :inclamo do
          resources :website_widgets, only: [:show, :update] do
            get :preview, on: :member
          end
          scope :support, controller: :support do
            get 'metadata', action: :metadata
            post 'uploads', action: :upload
            get 'requests', action: :index
            post 'requests', action: :create
            get 'requests/:id', action: :show
            post 'requests/:id/replies', action: :reply
            post 'requests/:id/read', action: :read
            post 'requests/:id/retry/:uuid', action: :retry_delivery
            get 'requests/:id/attachments/:file_id', action: :attachment
            get 'requests/:id/uploads/:file_id', action: :upload_download
            post 'requests/:id/recipient', action: :recipient
            post 'requests/:id/recipient/verify', action: :verify_recipient
          end
          resource :workspace_layout, only: [:show, :update, :destroy] do
            get :administration
            put :administer
          end
          resource :status, only: [:show], controller: 'status'
          resource :setup, only: [:show, :update], controller: 'setup' do
            post :complete
          end
          resources :order_roles, only: [:index, :create, :update, :destroy]
          resources :ai_policies, only: [:index, :update]
          post 'article_previews/:id', to: 'article_previews#create'
          scope 'conversations/:conversation_id' do
            resources :ai_proposals, only: [:index], controller: '/api/v1/accounts/inclamo/ai_proposals' do
              member do
                post :approve
                post :reject
                post :refresh
                post :verify_identity
              end
            end
          end
          resources :rule_presets, only: [:index, :update]
          resources :macro_previews, only: [:create]
          resources :macro_confirmations, only: [:create]
          resources :discount_presets, only: [:index, :create, :update, :destroy]
          resources :discount_grants, only: [:index, :create, :destroy]
          resources :sla_policies, only: [:index, :create, :update, :destroy] do
            collection do
              post :reorder
              get :summary
            end
          end
          get 'conversations/:conversation_id/sla', to: '/api/v1/accounts/inclamo/conversation_slas#show'
          namespace :ai do
            resource :connection, only: [:show, :create, :destroy], controller: '/api/v1/accounts/inclamo/ai_connections'
            scope 'conversations/:conversation_id', controller: '/api/v1/accounts/inclamo/ai_conversations' do
              get 'messages', action: :messages
              post 'reply', action: :reply
              post 'labels', action: :labels
              get 'orders', action: :orders
              post 'proposals', action: :propose
              get 'proposals/:id', action: :proposal
              post 'proposals/:id/execute', action: :execute
            end
          end
          namespace :shopify do
            resource :connection, only: [:show, :create, :destroy], controller: '/api/v1/accounts/inclamo/shopify_connections' do
              post :recheck
            end
            scope 'conversations/:conversation_id', controller: '/api/v1/accounts/inclamo/conversation_panels' do
              get 'panel', action: :show
              get 'lookup', action: :lookup
              get 'marks', action: :marks
              post 'customer', action: :choose_customer
              delete 'customer', action: :forget_customer
              put 'order', action: :mark_order
              delete 'order', action: :clear_order
            end
            scope 'conversations/:conversation_id' do
              post 'actions/refund_preview', to: '/api/v1/accounts/inclamo/order_actions#refund_preview'
              post 'actions/cancel_preview', to: '/api/v1/accounts/inclamo/order_actions#cancel_preview'
              post 'actions/new_order_preview', to: '/api/v1/accounts/inclamo/order_actions#new_order_preview'
              get 'actions/new_order_prefill', to: '/api/v1/accounts/inclamo/order_actions#new_order_prefill'
              get 'products', to: '/api/v1/accounts/inclamo/products#index'
              post 'actions/edit_items_preview', to: '/api/v1/accounts/inclamo/order_actions#edit_items_preview'
              resources :actions, only: [:index, :create, :show], controller: '/api/v1/accounts/inclamo/order_actions'
            end
          end
        end
      end
    end
  end
end
