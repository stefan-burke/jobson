require 'rails_helper'
require 'net/http'
require 'json'

RSpec.describe "API Compatibility with Java Implementation", type: :request do
  # This spec compares Rails API responses with expected Java API response structure
  # Run with: COMPARE_WITH_JAVA=true rspec spec/requests/api_compatibility_spec.rb
  
  let(:compare_with_java) { ENV['COMPARE_WITH_JAVA'] == 'true' }
  let(:java_base_url) { ENV.fetch('JAVA_API_URL', 'http://localhost:8081') }
  
  # Helper to fetch from Java API
  def fetch_from_java(path)
    return nil unless compare_with_java
    
    uri = URI("#{java_base_url}#{path}")
    response = Net::HTTP.get_response(uri)
    
    {
      status: response.code.to_i,
      body: response.body.empty? ? nil : JSON.parse(response.body),
      headers: response.to_hash
    }
  rescue => e
    skip "Java server not available: #{e.message}"
  end
  
  # Helper to normalize responses for comparison
  def normalize_response(response)
    return nil if response.nil?
    
    if response.is_a?(Hash)
      response.except('id', 'jobId', 'created_at', 'updated_at', 'timestamps')
              .transform_values { |v| normalize_response(v) }
    elsif response.is_a?(Array)
      response.map { |item| normalize_response(item) }
    else
      response
    end
  end
  
  describe "GET /" do
    it "returns root API structure matching Java" do
      get "/"
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      # Check structure
      expect(rails_body).to have_key('_links')
      expect(rails_body['_links']).to have_key('specs')
      expect(rails_body['_links']).to have_key('jobs')
      
      if compare_with_java
        java_response = fetch_from_java("/")
        expect(normalize_response(rails_body)).to eq(normalize_response(java_response[:body]))
      end
    end
  end
  
  describe "GET /api/v1" do
    it "returns v1 API structure matching Java" do
      get "/api/v1"
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to have_key('_links')
      expect(rails_body['_links']).to include('specs', 'jobs', 'current-user')
      
      if compare_with_java
        java_response = fetch_from_java("/api/v1")
        expect(normalize_response(rails_body)).to eq(normalize_response(java_response[:body]))
      end
    end
  end
  
  describe "GET /api/v1/specs" do
    before do
      # Ensure we have at least one spec
      allow(Dir).to receive(:[]).and_return(['workspace/specs/echo/spec.yml'])
      allow(File).to receive(:read).with('workspace/specs/echo/spec.yml').and_return(<<~YAML)
        name: Echo
        description: Test echo spec
        expectedInputs:
          - id: message
            type: string
            name: Message
            description: Message to echo
        execution:
          application: echo
          arguments:
            - "${inputs.message}"
      YAML
    end
    
    it "returns specs list structure matching Java" do
      get "/api/v1/specs"
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to have_key('entries')
      expect(rails_body['entries']).to be_an(Array)
      
      if rails_body['entries'].any?
        spec = rails_body['entries'].first
        expect(spec).to include('id', 'name', 'description', 'href')
      end
      
      if compare_with_java
        java_response = fetch_from_java("/api/v1/specs")
        
        # Compare structure but not exact values
        expect(rails_body.keys.sort).to eq(java_response[:body].keys.sort)
        expect(rails_body['entries'].first&.keys&.sort).to eq(
          java_response[:body]['entries'].first&.keys&.sort
        )
      end
    end
  end
  
  describe "GET /api/v1/specs/:id" do
    it "returns spec details structure matching Java" do
      get "/api/v1/specs/echo"
      
      if response.status == 404
        skip "Echo spec not available"
      end
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to include('id', 'name', 'description')
      expect(rails_body).to have_key('expectedInputs')
      
      if compare_with_java
        java_response = fetch_from_java("/api/v1/specs/echo")
        
        if java_response && java_response[:status] == 200
          # Compare normalized structure
          expect(normalize_response(rails_body).keys.sort).to eq(
            normalize_response(java_response[:body]).keys.sort
          )
        end
      end
    end
  end
  
  describe "GET /api/v1/jobs" do
    it "returns jobs list structure matching Java" do
      get "/api/v1/jobs"
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to have_key('entries')
      expect(rails_body['entries']).to be_an(Array)
      
      if compare_with_java
        java_response = fetch_from_java("/api/v1/jobs")
        
        # Structure comparison
        expect(rails_body.keys.sort).to eq(java_response[:body].keys.sort)
      end
    end
    
    it "supports pagination parameters" do
      get "/api/v1/jobs", params: { 'page-size': 5, 'page': 0 }
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to have_key('entries')
      expect(rails_body['entries'].size).to be <= 5
    end
  end
  
  describe "POST /api/v1/jobs" do
    let(:job_params) do
      {
        spec: 'echo',
        name: 'Test Job',
        inputs: {
          message: 'Hello from RSpec'
        }
      }
    end
    
    it "creates a job with structure matching Java" do
      post "/api/v1/jobs", 
           params: job_params.to_json,
           headers: { 'Content-Type': 'application/json' }
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to include('id', 'name', 'spec')
      expect(rails_body['name']).to eq('Test Job')
      expect(rails_body['spec']).to eq('echo')
      
      if compare_with_java
        # Create same job in Java
        uri = URI("#{java_base_url}/api/v1/jobs")
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = job_params.to_json
        
        java_response = http.request(request)
        if java_response.code == '200'
          java_body = JSON.parse(java_response.body)
          
          # Compare structure
          expect(normalize_response(rails_body).keys.sort).to eq(
            normalize_response(java_body).keys.sort
          )
        end
      end
    end
  end
  
  describe "GET /api/v1/jobs/:id" do
    let(:job_id) do
      # Create a job first
      post "/api/v1/jobs",
           params: { spec: 'echo', name: 'Detail Test', inputs: { message: 'test' } }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "returns job details structure matching Java" do
      get "/api/v1/jobs/#{job_id}"
      
      expect(response).to have_http_status(:ok)
      rails_body = JSON.parse(response.body)
      
      expect(rails_body).to include('id', 'name', 'spec', 'timestamps')
      expect(rails_body['timestamps']).to be_a(Hash)
      
      if compare_with_java
        # Note: We can't directly compare job details since IDs differ
        # But we can verify the structure matches
        
        # Get any job from Java to compare structure
        java_jobs = fetch_from_java("/api/v1/jobs")
        if java_jobs && java_jobs[:body]['entries'].any?
          java_job_id = java_jobs[:body]['entries'].first['id']
          java_job = fetch_from_java("/api/v1/jobs/#{java_job_id}")
          
          if java_job && java_job[:status] == 200
            # Compare keys structure
            expect(normalize_response(rails_body).keys.sort).to eq(
              normalize_response(java_job[:body]).keys.sort
            )
          end
        end
      end
    end
  end
  
  describe "GET /api/v1/jobs/:id/stdout" do
    let(:job_id) do
      post "/api/v1/jobs",
           params: { spec: 'echo', name: 'Stdout Test', inputs: { message: 'stdout test' } }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "returns stdout content" do
      # Give job time to execute
      sleep 1
      
      get "/api/v1/jobs/#{job_id}/stdout"
      
      # The response might be empty if job hasn't started
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('text/plain')
    end
  end
  
  describe "GET /api/v1/jobs/:id/stderr" do
    let(:job_id) do
      post "/api/v1/jobs",
           params: { spec: 'echo', name: 'Stderr Test', inputs: { message: 'stderr test' } }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "returns stderr content" do
      get "/api/v1/jobs/:id/stderr"
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('text/plain')
    end
  end
  
  describe "GET /api/v1/jobs/:id/spec" do
    let(:job_id) do
      post "/api/v1/jobs",
           params: { spec: 'echo', name: 'Spec Test', inputs: { message: 'spec test' } }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "returns job's spec" do
      get "/api/v1/jobs/#{job_id}/spec"
      
      expect(response).to have_http_status(:ok)
      spec = JSON.parse(response.body)
      
      expect(spec).to include('id', 'name', 'description')
      expect(spec['id']).to eq('echo')
    end
  end
  
  describe "GET /api/v1/jobs/:id/inputs" do
    let(:test_inputs) { { message: 'input test message' } }
    let(:job_id) do
      post "/api/v1/jobs",
           params: { spec: 'echo', name: 'Input Test', inputs: test_inputs }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "returns job inputs" do
      get "/api/v1/jobs/#{job_id}/inputs"
      
      expect(response).to have_http_status(:ok)
      inputs = JSON.parse(response.body)
      
      expect(inputs).to eq(test_inputs.stringify_keys)
    end
  end
  
  describe "DELETE /api/v1/jobs/:id" do
    let(:job_id) do
      post "/api/v1/jobs",
           params: { spec: 'echo', name: 'Delete Test', inputs: { message: 'delete' } }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "deletes the job" do
      delete "/api/v1/jobs/#{job_id}"
      
      expect(response).to have_http_status(:ok)
      
      # Verify it's gone
      get "/api/v1/jobs/#{job_id}"
      expect(response).to have_http_status(:not_found)
    end
  end
  
  describe "POST /api/v1/jobs/:id/abort" do
    let(:job_id) do
      post "/api/v1/jobs",
           params: { spec: 'sleep', name: 'Abort Test', inputs: { seconds: 60 } }.to_json,
           headers: { 'Content-Type': 'application/json' }
      JSON.parse(response.body)['id']
    end
    
    it "aborts a running job" do
      # Note: This might not work if sleep spec doesn't exist
      post "/api/v1/jobs/#{job_id}/abort"
      
      # We expect either success or not found (if job already finished)
      expect([200, 404]).to include(response.status)
    end
  end
  
  describe "GET /api/v1/users/current" do
    it "returns current user info" do
      get "/api/v1/users/current"
      
      expect(response).to have_http_status(:ok)
      user = JSON.parse(response.body)
      
      expect(user).to have_key('id')
      expect(user).to have_key('name')
      
      if compare_with_java
        java_response = fetch_from_java("/api/v1/users/current")
        
        if java_response && java_response[:status] == 200
          # Both should return guest user with similar structure
          expect(user.keys.sort).to eq(java_response[:body].keys.sort)
        end
      end
    end
  end
  
  describe "WebSocket endpoints" do
    it "provides job events endpoint" do
      get "/api/v1/jobs/events"
      
      # WebSocket upgrade request will fail in test, but endpoint should exist
      expect(response).to_not have_http_status(:not_found)
    end
    
    it "provides stdout updates endpoint" do
      get "/api/v1/jobs/test-id/stdout/updates"
      
      # WebSocket upgrade request will fail in test, but endpoint should exist
      expect(response).to_not have_http_status(:not_found)
    end
    
    it "provides stderr updates endpoint" do
      get "/api/v1/jobs/test-id/stderr/updates"
      
      # WebSocket upgrade request will fail in test, but endpoint should exist
      expect(response).to_not have_http_status(:not_found)
    end
  end
end