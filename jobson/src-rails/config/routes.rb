Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Define v1 API routes as a reusable concern
  concern :api_v1_routes do
    # Root for this version
    get '', to: 'api/v1/root#index'
    
    # WebSocket routes
    get 'jobs/events', to: 'api/v1/jobs#events'
    get 'jobs/:id/stdout/updates', to: 'api/v1/jobs#stdout_updates'
    get 'jobs/:id/stderr/updates', to: 'api/v1/jobs#stderr_updates'
    
    # Specs
    get 'specs', to: 'api/v1/job_specs#index'
    get 'specs/:id', to: 'api/v1/job_specs#show'
    
    # Jobs
    get 'jobs', to: 'api/v1/jobs#index'
    post 'jobs', to: 'api/v1/jobs#create'
    get 'jobs/:id', to: 'api/v1/jobs#show'
    delete 'jobs/:id', to: 'api/v1/jobs#destroy'
    post 'jobs/:id/abort', to: 'api/v1/jobs#abort'
    get 'jobs/:id/stdout', to: 'api/v1/jobs#stdout'
    get 'jobs/:id/stderr', to: 'api/v1/jobs#stderr'
    get 'jobs/:id/spec', to: 'api/v1/jobs#spec'
    get 'jobs/:id/inputs', to: 'api/v1/jobs#inputs'
    get 'jobs/:id/outputs', to: 'api/v1/jobs#outputs'
    get 'jobs/:id/outputs/:output_id', to: 'api/v1/jobs#output'
    
    # Users
    get 'users/current', to: 'api/v1/users#current'
  end

  # Mount the API routes at both /api/v1 and /v1
  scope '/api/v1' do
    concerns :api_v1_routes
  end
  
  scope '/v1' do
    concerns :api_v1_routes
  end

  # Also keep the namespace structure for backward compatibility
  namespace :api do
    namespace :v1 do
      # This ensures the controllers are still found in the api/v1 module
    end
  end

  # WebSocket routes
  mount ActionCable.server => '/cable'
  
  # Root API response
  root to: 'api/v1/root#index'
end
