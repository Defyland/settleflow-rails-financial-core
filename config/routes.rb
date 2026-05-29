Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "health/readiness#show"
  get "metrics" => "observability/metrics#show"

  namespace :v1 do
    resources :customers, only: [ :index, :show, :create ]
    resources :wallets, only: [ :index, :show, :create ] do
      member do
        get :balance
        get :statement
      end
    end
    resources :fundings, only: [ :index, :show, :create ]
    resources :transfers, only: [ :index, :show, :create ]
    resources :pix_payments, only: [ :index, :show, :create ] do
      post :settle, on: :member
    end
    resources :ledger_entries, only: [ :index, :show ]
    resources :reconciliation_runs, only: [ :index, :show, :create ]
    resources :outbox_events, only: [ :index ]
  end
end
