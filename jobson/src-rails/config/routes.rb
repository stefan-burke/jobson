Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # WebSocket routes (must come before resources to have priority)
  get '/api/v1/jobs/events', to: 'api/v1/jobs#events'
  get '/api/v1/jobs/:id/stdout/updates', to: 'api/v1/jobs#stdout_updates'
  get '/api/v1/jobs/:id/stderr/updates', to: 'api/v1/jobs#stderr_updates'

  # API v1 routes
  namespace :api do
    namespace :v1 do
      root to: 'root#index'
      
      resources :specs, controller: 'job_specs', only: [:index, :show]
      
      resources :jobs, only: [:index, :show, :create, :destroy] do
        member do
          post :abort
          get :stdout
          get :stderr
          get :spec
          get :inputs
          get :outputs
          get 'outputs/:output_id', action: :output, as: :output
        end
      end
      
      # Users endpoint (fake - always returns guest)
      namespace :users do
        get :current
      end
    end
  end

  # WebSocket routes
  mount ActionCable.server => '/cable'
  
  # Root API response
  root to: 'api/v1/root#index'
end
