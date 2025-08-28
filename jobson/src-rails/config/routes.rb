Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # WebSocket routes (must come before resources to have priority)
  get '/api/v1/jobs/events', to: 'api/v1/jobs#events'
  get '/api/v1/jobs/:id/stdout/updates', to: 'api/v1/jobs#stdout_updates'
  get '/api/v1/jobs/:id/stderr/updates', to: 'api/v1/jobs#stderr_updates'
  get '/v1/jobs/events', to: 'api/v1/jobs#events'
  get '/v1/jobs/:id/stdout/updates', to: 'api/v1/jobs#stdout_updates'
  get '/v1/jobs/:id/stderr/updates', to: 'api/v1/jobs#stderr_updates'

  # API v1 routes with /api prefix
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
      
      # Users endpoint
      namespace :users do
        get :current
      end
    end
  end
  
  # V1 routes without /api prefix (for Java compatibility)
  namespace :v1, path: 'v1', module: 'api/v1' do
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
    
    # Users endpoint
    namespace :users do
      get :current
    end
  end

  # WebSocket routes
  mount ActionCable.server => '/cable'
  
  # Root API response (matches Java's structure)
  root to: 'root#index'
end
