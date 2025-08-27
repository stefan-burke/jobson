#!/usr/bin/env ruby

# Direct API response comparison tool
# Usage: ruby compare-api-responses.rb [endpoint]
# Example: ruby compare-api-responses.rb /api/v1/specs

require 'net/http'
require 'json'
require 'optparse'
require 'set'

class APIComparator
  JAVA_URL = ENV.fetch('JAVA_API_URL', 'http://localhost:8081')
  RAILS_URL = ENV.fetch('RAILS_API_URL', 'http://localhost:3000')
  
  # Fields to ignore in comparison
  IGNORE_FIELDS = %w[id jobId created_at updated_at timestamps].to_set
  
  def initialize(options = {})
    @verbose = options[:verbose]
    @ignore_ids = options[:ignore_ids]
    @show_raw = options[:show_raw]
  end
  
  def compare_endpoint(endpoint, method: 'GET', body: nil)
    puts "\n" + "="*60
    puts "Comparing: #{method} #{endpoint}"
    puts "="*60
    
    # Fetch from both APIs
    java_response = fetch_response(JAVA_URL, endpoint, method, body)
    rails_response = fetch_response(RAILS_URL, endpoint, method, body)
    
    # Show raw responses if requested
    if @show_raw
      puts "\n--- Java Response ---"
      puts JSON.pretty_generate(java_response[:body]) if java_response[:body]
      puts "\n--- Rails Response ---"
      puts JSON.pretty_generate(rails_response[:body]) if rails_response[:body]
    end
    
    # Compare status codes
    if java_response[:status] != rails_response[:status]
      puts "❌ Status code mismatch:"
      puts "   Java:  #{java_response[:status]}"
      puts "   Rails: #{rails_response[:status]}"
      return false
    else
      puts "✓ Status codes match: #{java_response[:status]}"
    end
    
    # Compare response bodies
    if java_response[:body] && rails_response[:body]
      java_normalized = normalize_response(java_response[:body])
      rails_normalized = normalize_response(rails_response[:body])
      
      differences = deep_compare(java_normalized, rails_normalized)
      
      if differences.empty?
        puts "✓ Response bodies match (ignoring IDs and timestamps)"
        return true
      else
        puts "❌ Response bodies differ:"
        differences.each { |diff| puts "   - #{diff}" }
        
        if @verbose
          puts "\n--- Normalized Java ---"
          puts JSON.pretty_generate(java_normalized)
          puts "\n--- Normalized Rails ---"
          puts JSON.pretty_generate(rails_normalized)
        end
        
        return false
      end
    elsif java_response[:body] || rails_response[:body]
      puts "❌ One response has body, other doesn't"
      return false
    else
      puts "✓ Both responses have no body"
      return true
    end
  end
  
  def compare_all_basic_endpoints
    endpoints = [
      '/',
      '/api/v1',
      '/api/v1/specs',
      '/api/v1/specs/echo',
      '/api/v1/jobs',
      '/api/v1/users/current'
    ]
    
    results = {}
    
    endpoints.each do |endpoint|
      begin
        results[endpoint] = compare_endpoint(endpoint)
      rescue => e
        puts "❌ Error testing #{endpoint}: #{e.message}"
        results[endpoint] = false
      end
    end
    
    # Summary
    puts "\n" + "="*60
    puts "SUMMARY"
    puts "="*60
    
    passed = results.values.count(true)
    failed = results.values.count(false)
    
    results.each do |endpoint, success|
      status = success ? "✓" : "✗"
      puts "#{status} #{endpoint}"
    end
    
    puts "\nPassed: #{passed}/#{results.size}"
    
    passed == results.size
  end
  
  def test_job_lifecycle
    puts "\n" + "="*60
    puts "Testing Job Lifecycle"
    puts "="*60
    
    # Create a job on both servers
    job_data = {
      spec: 'echo',
      name: 'Comparison Test Job',
      inputs: { message: 'Testing API compatibility' }
    }
    
    puts "\n1. Creating jobs..."
    java_job = create_job(JAVA_URL, job_data)
    rails_job = create_job(RAILS_URL, job_data)
    
    if java_job && rails_job
      puts "✓ Jobs created"
      puts "   Java ID:  #{java_job['id']}"
      puts "   Rails ID: #{rails_job['id']}"
      
      # Compare job structure (ignoring IDs)
      java_normalized = normalize_response(java_job)
      rails_normalized = normalize_response(rails_job)
      
      differences = deep_compare(java_normalized, rails_normalized)
      if differences.empty?
        puts "✓ Job creation responses match"
      else
        puts "❌ Job creation responses differ:"
        differences.each { |diff| puts "   - #{diff}" }
      end
      
      # Test job endpoints
      puts "\n2. Testing job-specific endpoints..."
      
      # Test job details
      compare_job_endpoint(java_job['id'], rails_job['id'], '')
      
      # Test job spec
      compare_job_endpoint(java_job['id'], rails_job['id'], '/spec')
      
      # Test job inputs
      compare_job_endpoint(java_job['id'], rails_job['id'], '/inputs')
      
      # Wait for completion
      puts "\n3. Waiting for job completion..."
      sleep 2
      
      # Test stdout
      compare_job_endpoint(java_job['id'], rails_job['id'], '/stdout', text: true)
      
      # Test stderr
      compare_job_endpoint(java_job['id'], rails_job['id'], '/stderr', text: true)
      
      # Clean up
      puts "\n4. Cleaning up..."
      delete_job(JAVA_URL, java_job['id'])
      delete_job(RAILS_URL, rails_job['id'])
      puts "✓ Jobs deleted"
      
      true
    else
      puts "❌ Failed to create jobs"
      false
    end
  end
  
  private
  
  def fetch_response(base_url, endpoint, method = 'GET', body = nil)
    uri = URI("#{base_url}#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = case method.upcase
    when 'POST'
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json' if body
      req.body = body.to_json if body
      req
    when 'DELETE'
      Net::HTTP::Delete.new(uri)
    else
      Net::HTTP::Get.new(uri)
    end
    
    request['Accept'] = 'application/json'
    
    response = http.request(request)
    
    {
      status: response.code.to_i,
      body: response.body.empty? ? nil : (
        response.content_type&.include?('json') ? JSON.parse(response.body) : response.body
      ),
      headers: response.to_hash
    }
  rescue => e
    raise "Failed to fetch from #{base_url}#{endpoint}: #{e.message}"
  end
  
  def create_job(base_url, job_data)
    response = fetch_response(base_url, '/api/v1/jobs', 'POST', job_data)
    response[:body] if response[:status] == 200
  end
  
  def delete_job(base_url, job_id)
    fetch_response(base_url, "/api/v1/jobs/#{job_id}", 'DELETE')
  rescue
    # Ignore deletion errors
  end
  
  def compare_job_endpoint(java_id, rails_id, suffix, text: false)
    java_response = fetch_response(JAVA_URL, "/api/v1/jobs/#{java_id}#{suffix}")
    rails_response = fetch_response(RAILS_URL, "/api/v1/jobs/#{rails_id}#{suffix}")
    
    endpoint_name = suffix.empty? ? 'job details' : suffix.gsub('/', '')
    
    if java_response[:status] != rails_response[:status]
      puts "❌ #{endpoint_name}: Status mismatch (Java: #{java_response[:status]}, Rails: #{rails_response[:status]})"
      return false
    end
    
    if text
      # For text responses, just check they're both strings
      if java_response[:body].is_a?(String) && rails_response[:body].is_a?(String)
        puts "✓ #{endpoint_name}: Both return text"
      else
        puts "❌ #{endpoint_name}: Response type mismatch"
      end
    else
      java_normalized = normalize_response(java_response[:body])
      rails_normalized = normalize_response(rails_response[:body])
      
      differences = deep_compare(java_normalized, rails_normalized)
      
      if differences.empty?
        puts "✓ #{endpoint_name}: Responses match"
      else
        puts "❌ #{endpoint_name}: Responses differ"
        differences.first(3).each { |diff| puts "     - #{diff}" } if @verbose
      end
    end
  end
  
  def normalize_response(data)
    return nil if data.nil?
    
    case data
    when Hash
      result = {}
      data.each do |key, value|
        next if @ignore_ids && IGNORE_FIELDS.include?(key)
        
        # Normalize URLs to just paths
        if value.is_a?(String) && value.match?(%r{https?://})
          result[key] = value.gsub(%r{https?://[^/]+}, '')
        else
          result[key] = normalize_response(value)
        end
      end
      result
    when Array
      data.map { |item| normalize_response(item) }
    else
      data
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
      java_keys = java_val.keys.to_set
      rails_keys = rails_val.keys.to_set
      
      missing_in_rails = java_keys - rails_keys
      missing_in_java = rails_keys - java_keys
      
      if missing_in_rails.any?
        differences << "Missing in Rails at #{path.join('.')}: #{missing_in_rails.to_a.join(', ')}"
      end
      
      if missing_in_java.any?
        differences << "Missing in Java at #{path.join('.')}: #{missing_in_java.to_a.join(', ')}"
      end
      
      (java_keys & rails_keys).each do |key|
        differences.concat(deep_compare(java_val[key], rails_val[key], path + [key]))
      end
      
    when Array
      if java_val.length != rails_val.length
        differences << "Array length at #{path.join('.')}: Java=#{java_val.length}, Rails=#{rails_val.length}"
      else
        java_val.each_with_index do |item, index|
          differences.concat(deep_compare(item, rails_val[index], path + ["[#{index}]"]))
        end
      end
      
    else
      if java_val != rails_val
        differences << "Value at #{path.join('.')}: Java=#{java_val.inspect}, Rails=#{rails_val.inspect}"
      end
    end
    
    differences
  end
end

# Command line interface
if __FILE__ == $0
  options = {
    verbose: false,
    ignore_ids: true,
    show_raw: false
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby compare-api-responses.rb [options] [endpoint]"
    
    opts.on("-v", "--verbose", "Show detailed differences") do
      options[:verbose] = true
    end
    
    opts.on("-r", "--raw", "Show raw responses") do
      options[:show_raw] = true
    end
    
    opts.on("-i", "--include-ids", "Include IDs in comparison") do
      options[:ignore_ids] = false
    end
    
    opts.on("-l", "--lifecycle", "Test full job lifecycle") do
      options[:lifecycle] = true
    end
    
    opts.on("-a", "--all", "Test all basic endpoints") do
      options[:all] = true
    end
    
    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!
  
  comparator = APIComparator.new(options)
  
  begin
    # Verify servers are running
    puts "Java API:  #{APIComparator::JAVA_URL}"
    puts "Rails API: #{APIComparator::RAILS_URL}"
    
    Net::HTTP.get(URI("#{APIComparator::JAVA_URL}/api/v1"))
    puts "✓ Java server is running"
    
    Net::HTTP.get(URI("#{APIComparator::RAILS_URL}/api/v1"))
    puts "✓ Rails server is running"
    
    if options[:lifecycle]
      success = comparator.test_job_lifecycle
    elsif options[:all]
      success = comparator.compare_all_basic_endpoints
    elsif ARGV[0]
      success = comparator.compare_endpoint(ARGV[0])
    else
      puts "\nNo endpoint specified. Use -h for help."
      puts "\nExample usage:"
      puts "  ruby compare-api-responses.rb /api/v1/specs"
      puts "  ruby compare-api-responses.rb --all"
      puts "  ruby compare-api-responses.rb --lifecycle"
      exit 1
    end
    
    exit(success ? 0 : 1)
    
  rescue Errno::ECONNREFUSED => e
    puts "❌ Server not running: #{e.message}"
    puts "\nMake sure both servers are running:"
    puts "  Java:  java -jar target/jobson.jar server config.yml"
    puts "  Rails: cd src-rails && rails server"
    exit 1
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace if options[:verbose]
    exit 1
  end
end