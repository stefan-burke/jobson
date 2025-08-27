require 'test_helper'
require 'net/http'
require 'json'
require 'set'

class ApiComparisonTest < ActiveSupport::TestCase
  JAVA_BASE_URL = ENV.fetch('JAVA_API_URL', 'http://localhost:8081')
  RAILS_BASE_URL = ENV.fetch('RAILS_API_URL', 'http://localhost:3000')
  
  # Fields to ignore when comparing responses
  IGNORE_FIELDS = %w[id jobId created_at updated_at timestamps].to_set
  
  # Fields that may have slight format differences but should be semantically equal
  FLEXIBLE_FIELDS = %w[href _links].to_set

  class << self
    def startup
      # Ensure both servers are running
      verify_servers!
    end

    def verify_servers!
      verify_server!(JAVA_BASE_URL, "Java")
      verify_server!(RAILS_BASE_URL, "Rails")
    end

    def verify_server!(base_url, name)
      uri = URI("#{base_url}/api/v1")
      response = Net::HTTP.get_response(uri)
      raise "#{name} server not responding at #{base_url}" unless response.code == '200'
      puts "✓ #{name} server responding at #{base_url}"
    rescue => e
      raise "Cannot connect to #{name} server at #{base_url}: #{e.message}"
    end
  end

  def setup
    @job_ids = { java: nil, rails: nil }
  end

  def teardown
    # Clean up created jobs
    @job_ids.each do |server, job_id|
      delete_job(server, job_id) if job_id
    end
  end

  # Test root endpoint
  test "root endpoint returns same structure" do
    java_response = fetch_json(:java, "/")
    rails_response = fetch_json(:rails, "/")
    
    assert_api_responses_equal(java_response, rails_response, "Root endpoint")
  end

  # Test API v1 root
  test "api v1 root returns same structure" do
    java_response = fetch_json(:java, "/api/v1")
    rails_response = fetch_json(:rails, "/api/v1")
    
    assert_api_responses_equal(java_response, rails_response, "API v1 root")
  end

  # Test specs listing
  test "specs endpoint returns same structure" do
    java_response = fetch_json(:java, "/api/v1/specs")
    rails_response = fetch_json(:rails, "/api/v1/specs")
    
    assert_api_responses_equal(java_response, rails_response, "Specs listing")
    
    # Verify both have the same specs
    java_specs = java_response['entries'].map { |s| s['id'] }.sort
    rails_specs = rails_response['entries'].map { |s| s['id'] }.sort
    
    assert_equal java_specs, rails_specs, "Both APIs should have the same specs available"
  end

  # Test individual spec retrieval
  test "individual spec returns same structure" do
    # First get available specs
    specs_response = fetch_json(:rails, "/api/v1/specs")
    skip "No specs available" if specs_response['entries'].empty?
    
    spec_id = specs_response['entries'].first['id']
    
    java_response = fetch_json(:java, "/api/v1/specs/#{spec_id}")
    rails_response = fetch_json(:rails, "/api/v1/specs/#{spec_id}")
    
    assert_api_responses_equal(java_response, rails_response, "Spec '#{spec_id}'")
  end

  # Test echo spec specifically
  test "echo spec details match" do
    java_response = fetch_json(:java, "/api/v1/specs/echo")
    rails_response = fetch_json(:rails, "/api/v1/specs/echo")
    
    assert_api_responses_equal(java_response, rails_response, "Echo spec")
    
    # Verify specific fields
    assert_equal java_response['name'], rails_response['name']
    assert_equal java_response['description'], rails_response['description']
    
    # Verify inputs structure
    if java_response['expectedInputs'] && rails_response['expectedInputs']
      assert_equal java_response['expectedInputs'].length, 
                   rails_response['expectedInputs'].length,
                   "Number of inputs should match"
    end
  end

  # Test jobs listing
  test "jobs endpoint returns same structure" do
    java_response = fetch_json(:java, "/api/v1/jobs")
    rails_response = fetch_json(:rails, "/api/v1/jobs")
    
    assert_api_responses_equal(java_response, rails_response, "Jobs listing")
  end

  # Test job creation
  test "job creation returns same structure" do
    job_request = {
      spec: 'echo',
      name: 'Test Echo Job',
      inputs: {
        message: 'Hello from comparison test'
      }
    }
    
    java_response = create_job(:java, job_request)
    rails_response = create_job(:rails, job_request)
    
    # Store IDs for cleanup
    @job_ids[:java] = java_response['id']
    @job_ids[:rails] = rails_response['id']
    
    assert_api_responses_equal(java_response, rails_response, "Job creation")
    
    # Verify key fields match
    assert_equal java_response['name'], rails_response['name']
    assert_equal java_response['spec'], rails_response['spec']
  end

  # Test job retrieval
  test "job details return same structure" do
    job_request = {
      spec: 'echo',
      name: 'Test Job Details',
      inputs: {
        message: 'Testing job details endpoint'
      }
    }
    
    # Create jobs on both servers
    java_job = create_job(:java, job_request)
    rails_job = create_job(:rails, job_request)
    
    @job_ids[:java] = java_job['id']
    @job_ids[:rails] = rails_job['id']
    
    # Fetch job details
    java_details = fetch_json(:java, "/api/v1/jobs/#{java_job['id']}")
    rails_details = fetch_json(:rails, "/api/v1/jobs/#{rails_job['id']}")
    
    assert_api_responses_equal(java_details, rails_details, "Job details")
  end

  # Test job stdout endpoint
  test "job stdout endpoint returns same structure" do
    job_request = {
      spec: 'echo',
      name: 'Test Stdout',
      inputs: {
        message: 'Testing stdout endpoint'
      }
    }
    
    java_job = create_job(:java, job_request)
    rails_job = create_job(:rails, job_request)
    
    @job_ids[:java] = java_job['id']
    @job_ids[:rails] = rails_job['id']
    
    # Wait for jobs to complete
    wait_for_job_completion(:java, java_job['id'])
    wait_for_job_completion(:rails, rails_job['id'])
    
    java_stdout = fetch_raw(:java, "/api/v1/jobs/#{java_job['id']}/stdout")
    rails_stdout = fetch_raw(:rails, "/api/v1/jobs/#{rails_job['id']}/stdout")
    
    # Stdout content should be identical for the same input
    assert_equal java_stdout.strip, rails_stdout.strip, 
                 "Stdout content should match for identical job inputs"
  end

  # Test job inputs endpoint
  test "job inputs endpoint returns same structure" do
    job_request = {
      spec: 'echo',
      name: 'Test Inputs',
      inputs: {
        message: 'Testing inputs endpoint'
      }
    }
    
    java_job = create_job(:java, job_request)
    rails_job = create_job(:rails, job_request)
    
    @job_ids[:java] = java_job['id']
    @job_ids[:rails] = rails_job['id']
    
    java_inputs = fetch_json(:java, "/api/v1/jobs/#{java_job['id']}/inputs")
    rails_inputs = fetch_json(:rails, "/api/v1/jobs/#{rails_job['id']}/inputs")
    
    assert_api_responses_equal(java_inputs, rails_inputs, "Job inputs")
  end

  # Test job spec endpoint
  test "job spec endpoint returns same structure" do
    job_request = {
      spec: 'echo',
      name: 'Test Job Spec',
      inputs: {
        message: 'Testing job spec endpoint'
      }
    }
    
    java_job = create_job(:java, job_request)
    rails_job = create_job(:rails, job_request)
    
    @job_ids[:java] = java_job['id']
    @job_ids[:rails] = rails_job['id']
    
    java_spec = fetch_json(:java, "/api/v1/jobs/#{java_job['id']}/spec")
    rails_spec = fetch_json(:rails, "/api/v1/jobs/#{rails_job['id']}/spec")
    
    assert_api_responses_equal(java_spec, rails_spec, "Job spec via job")
  end

  # Test current user endpoint
  test "current user endpoint returns same structure" do
    java_response = fetch_json(:java, "/api/v1/users/current")
    rails_response = fetch_json(:rails, "/api/v1/users/current")
    
    assert_api_responses_equal(java_response, rails_response, "Current user")
  end

  # Test job deletion
  test "job deletion works on both APIs" do
    job_request = {
      spec: 'echo',
      name: 'Test Deletion',
      inputs: {
        message: 'Testing deletion'
      }
    }
    
    java_job = create_job(:java, job_request)
    rails_job = create_job(:rails, job_request)
    
    # Delete both jobs
    delete_job(:java, java_job['id'])
    delete_job(:rails, rails_job['id'])
    
    # Clear from cleanup list since we already deleted
    @job_ids[:java] = nil
    @job_ids[:rails] = nil
    
    # Verify both are gone (should return 404)
    assert_raises(RuntimeError) { fetch_json(:java, "/api/v1/jobs/#{java_job['id']}") }
    assert_raises(RuntimeError) { fetch_json(:rails, "/api/v1/jobs/#{rails_job['id']}") }
  end

  # Test pagination parameters
  test "jobs listing with pagination returns same structure" do
    # Create a few jobs to ensure pagination works
    3.times do |i|
      job_request = {
        spec: 'echo',
        name: "Pagination Test #{i}",
        inputs: { message: "Test #{i}" }
      }
      
      java_job = create_job(:java, job_request)
      rails_job = create_job(:rails, job_request)
      # These will be cleaned up in bulk later
    end
    
    # Test with page size
    java_response = fetch_json(:java, "/api/v1/jobs?page-size=2")
    rails_response = fetch_json(:rails, "/api/v1/jobs?page-size=2")
    
    assert_api_responses_equal(java_response, rails_response, "Jobs with pagination")
  end

  private

  def base_url(server)
    server == :java ? JAVA_BASE_URL : RAILS_BASE_URL
  end

  def fetch_json(server, path)
    response = fetch_raw(server, path)
    JSON.parse(response)
  end

  def fetch_raw(server, path)
    uri = URI("#{base_url(server)}#{path}")
    response = Net::HTTP.get_response(uri)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP #{response.code} from #{server} server: #{response.body}"
    end
    
    response.body
  end

  def create_job(server, job_data)
    uri = URI("#{base_url(server)}/api/v1/jobs")
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request.body = job_data.to_json
    
    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to create job on #{server}: HTTP #{response.code} - #{response.body}"
    end
    
    JSON.parse(response.body)
  end

  def delete_job(server, job_id)
    return unless job_id
    
    uri = URI("#{base_url(server)}/api/v1/jobs/#{job_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Delete.new(uri)
    response = http.request(request)
    
    # It's OK if the job doesn't exist (404)
    unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNotFound)
      puts "Warning: Failed to delete job #{job_id} on #{server}: HTTP #{response.code}"
    end
  rescue => e
    puts "Warning: Error deleting job #{job_id} on #{server}: #{e.message}"
  end

  def wait_for_job_completion(server, job_id, timeout: 10)
    start_time = Time.now
    
    loop do
      job = fetch_json(server, "/api/v1/jobs/#{job_id}")
      
      # Check if job has completed (has latestStatus that's not SUBMITTED)
      if job['latestStatus'] && !['SUBMITTED', 'RUNNING'].include?(job['latestStatus'])
        return job
      end
      
      if Time.now - start_time > timeout
        raise "Job #{job_id} on #{server} did not complete within #{timeout} seconds"
      end
      
      sleep 0.5
    end
  end

  def normalize_response(data)
    case data
    when Hash
      normalized = {}
      data.each do |key, value|
        next if IGNORE_FIELDS.include?(key)
        normalized[key] = normalize_response(value)
      end
      normalized
    when Array
      data.map { |item| normalize_response(item) }
    else
      data
    end
  end

  def assert_api_responses_equal(java_response, rails_response, context)
    # Normalize both responses
    normalized_java = normalize_response(java_response)
    normalized_rails = normalize_response(rails_response)
    
    # Deep comparison
    differences = deep_compare(normalized_java, normalized_rails)
    
    if differences.any?
      message = "API responses differ for #{context}:\n"
      differences.each do |diff|
        message += "  - #{diff}\n"
      end
      flunk message
    else
      pass
    end
  end

  def deep_compare(java_val, rails_val, path = [])
    differences = []
    
    if java_val.class != rails_val.class
      differences << "Type mismatch at #{path.join('.')}: Java=#{java_val.class}, Rails=#{rails_val.class}"
      return differences
    end
    
    case java_val
    when Hash
      # Check keys match
      java_keys = java_val.keys.to_set
      rails_keys = rails_val.keys.to_set
      
      missing_in_rails = java_keys - rails_keys
      missing_in_java = rails_keys - java_keys
      
      if missing_in_rails.any?
        differences << "Keys missing in Rails at #{path.join('.')}: #{missing_in_rails.to_a.join(', ')}"
      end
      
      if missing_in_java.any?
        differences << "Keys missing in Java at #{path.join('.')}: #{missing_in_java.to_a.join(', ')}"
      end
      
      # Compare common keys
      (java_keys & rails_keys).each do |key|
        new_path = path + [key]
        
        # Special handling for flexible fields
        if FLEXIBLE_FIELDS.include?(key)
          # Just check they're both present and same type
          if java_val[key].class != rails_val[key].class
            differences << "Type mismatch for flexible field at #{new_path.join('.')}"
          end
        else
          differences.concat(deep_compare(java_val[key], rails_val[key], new_path))
        end
      end
      
    when Array
      if java_val.length != rails_val.length
        differences << "Array length mismatch at #{path.join('.')}: Java=#{java_val.length}, Rails=#{rails_val.length}"
      else
        java_val.each_with_index do |item, index|
          differences.concat(deep_compare(item, rails_val[index], path + ["[#{index}]"]))
        end
      end
      
    else
      # Primitive values
      if java_val != rails_val
        # Special handling for timestamps and URLs
        unless flexible_value?(java_val, rails_val)
          differences << "Value mismatch at #{path.join('.')}: Java=#{java_val.inspect}, Rails=#{rails_val.inspect}"
        end
      end
    end
    
    differences
  end

  def flexible_value?(java_val, rails_val)
    # Allow slight differences in URLs (like port numbers)
    if java_val.is_a?(String) && rails_val.is_a?(String)
      # Check if both are URLs
      if java_val.include?('http') && rails_val.include?('http')
        # Remove host/port differences and compare paths
        java_path = java_val.gsub(%r{https?://[^/]+}, '')
        rails_path = rails_val.gsub(%r{https?://[^/]+}, '')
        return java_path == rails_path
      end
      
      # Check if both are timestamps in different formats
      if java_val.match?(/\d{4}-\d{2}-\d{2}/) && rails_val.match?(/\d{4}-\d{2}-\d{2}/)
        return true # Accept any timestamp format differences
      end
    end
    
    false
  end
end