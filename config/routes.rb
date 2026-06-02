Rails.application.routes.draw do
  root "ops/dashboard#show"

  resource :session
  resources :passwords, param: :token

  namespace :ops do
    root "dashboard#show"
    resources :wallets, only: [ :index, :show ]
    resources :pix_payments, only: [ :index, :show ] do
      member do
        post :settle
        post :reject
        post :reverse
      end
    end
    resources :med_cases, only: [ :index, :show ] do
      member do
        post :accept
        post :reject
      end
    end
    resources :outbox_events, only: [ :index ] do
      post :retry, on: :member
    end
    resources :reconciliation_runs, only: [ :index, :show ]
    resources :ledger_entries, only: [ :index, :show ]
    resources :audit_logs, only: [ :index ]
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "health/readiness#show"
  get "metrics" => "observability/metrics#show"

  namespace :v1 do
    resources :customers, only: [ :index, :show, :create ]
    resources :wallets, only: [ :index, :show, :create ] do
      member do
        get :balance
        get :balance_explanation
        get :statement
      end
    end
    resources :fundings, only: [ :index, :show, :create ]
    resources :transfers, only: [ :index, :show, :create ]
    resources :split_payments, only: [ :index, :show, :create ]
    resources :payouts, only: [ :index, :show, :create ] do
      post :settle, on: :member
    end
    resources :pix_payments, only: [ :index, :show, :create ] do
      post :settle, on: :member
    end
    resources :refunds, only: [ :index, :show, :create ]
    resources :med_cases, only: [ :index, :show, :create ] do
      member do
        post :accept
        post :reject
      end
    end
    resources :ledger_entries, only: [ :index, :show ]
    resources :reconciliation_runs, only: [ :index, :show, :create ]
    resources :outbox_events, only: [ :index ]
  end
end
