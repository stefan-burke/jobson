# API Comparison Tests

This directory contains comprehensive tests to ensure the Rails implementation of the Jobson API is fully compatible with the original Java implementation.

## Overview

The test suite compares API responses between the Java and Rails versions to ensure they return identical data structures and behavior (excluding auto-generated IDs and timestamps).

## Test Files

### 1. `run-api-comparison-tests.sh`
Full automated test suite that:
- Builds the Java application
- Starts both Java (port 8081) and Rails (port 3000) servers
- Runs comprehensive comparison tests
- Cleans up afterward

**Usage:**
```bash
./run-api-comparison-tests.sh
```

### 2. `src-rails/test/api_comparison_test.rb`
Rails test file using Minitest that runs detailed comparisons of all API endpoints.

**Usage:**
```bash
# With both servers running:
cd src-rails
JAVA_API_URL=http://localhost:8081 RAILS_API_URL=http://localhost:3000 \
  rails test test/api_comparison_test.rb
```

### 3. `src-rails/spec/requests/api_compatibility_spec.rb`
RSpec version of the compatibility tests with optional Java comparison.

**Usage:**
```bash
# Basic structure tests (Rails only):
cd src-rails
rspec spec/requests/api_compatibility_spec.rb

# With Java comparison:
COMPARE_WITH_JAVA=true JAVA_API_URL=http://localhost:8081 \
  rspec spec/requests/api_compatibility_spec.rb
```

### 4. `compare-api-responses.rb`
Interactive Ruby script for manual endpoint comparison and debugging.

**Usage:**
```bash
# Compare specific endpoint
ruby compare-api-responses.rb /api/v1/specs

# Test all basic endpoints
ruby compare-api-responses.rb --all

# Test full job lifecycle
ruby compare-api-responses.rb --lifecycle

# Verbose output with raw responses
ruby compare-api-responses.rb -v -r /api/v1/jobs

# Include IDs in comparison (normally ignored)
ruby compare-api-responses.rb --include-ids /api/v1/specs
```

## What's Tested

### Endpoints Covered:
- `GET /` - Root API
- `GET /api/v1` - API v1 root
- `GET /api/v1/specs` - List job specifications
- `GET /api/v1/specs/:id` - Get specific spec
- `GET /api/v1/jobs` - List jobs
- `POST /api/v1/jobs` - Create new job
- `GET /api/v1/jobs/:id` - Get job details
- `DELETE /api/v1/jobs/:id` - Delete job
- `GET /api/v1/jobs/:id/stdout` - Get job stdout
- `GET /api/v1/jobs/:id/stderr` - Get job stderr
- `GET /api/v1/jobs/:id/spec` - Get job's spec
- `GET /api/v1/jobs/:id/inputs` - Get job inputs
- `GET /api/v1/jobs/:id/outputs` - Get job outputs
- `POST /api/v1/jobs/:id/abort` - Abort running job
- `GET /api/v1/users/current` - Get current user

### WebSocket Endpoints:
- `/api/v1/jobs/events` - Job event stream
- `/api/v1/jobs/:id/stdout/updates` - Live stdout updates
- `/api/v1/jobs/:id/stderr/updates` - Live stderr updates

### Test Coverage:
- Response structure matching
- Status code verification
- Pagination parameters
- Job lifecycle (create, run, complete, delete)
- Error handling
- Content-Type headers
- Link structure in HAL responses

## Ignored Fields

The following fields are automatically ignored when comparing responses since they differ between implementations:
- `id` / `jobId` - Auto-generated unique identifiers
- `created_at` / `updated_at` - Rails timestamps
- `timestamps` - Timing information

## Manual Testing

### Start Both Servers:

1. **Start Java Server** (port 8081):
```bash
cd jobson
java -jar target/jobson-*.jar server config.yml
```

2. **Start Rails Server** (port 3000):
```bash
cd jobson/src-rails
rails server -p 3000
```

### Run Comparison:
```bash
# Quick test
ruby compare-api-responses.rb --all

# Full test suite
./run-api-comparison-tests.sh

# Specific endpoint debugging
ruby compare-api-responses.rb -v -r /api/v1/specs/echo
```

## Continuous Integration

The comparison tests can be integrated into CI pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run API Comparison Tests
  run: |
    cd jobson
    ./run-api-comparison-tests.sh
```

## Troubleshooting

### Common Issues:

1. **Port already in use**: Kill existing processes or change ports in scripts
2. **Specs not found**: Ensure workspace/specs directory exists with spec files
3. **Connection refused**: Wait for servers to fully start (check logs)
4. **Different responses**: Use verbose mode to see exact differences

### Debug Commands:

```bash
# Check if servers are responding
curl http://localhost:8081/api/v1
curl http://localhost:3000/api/v1

# View server logs
tail -f java-server.log
tail -f rails-server.log

# Compare specific field differences
ruby compare-api-responses.rb -v /api/v1/specs | grep "Missing"
```

## Adding New Tests

To add new endpoint comparisons:

1. Add to `api_comparison_test.rb`:
```ruby
test "new endpoint returns same structure" do
  java_response = fetch_json(:java, "/api/v1/new-endpoint")
  rails_response = fetch_json(:rails, "/api/v1/new-endpoint")
  assert_api_responses_equal(java_response, rails_response, "New endpoint")
end
```

2. Add to `compare-api-responses.rb` endpoint list:
```ruby
endpoints = [
  # ... existing endpoints
  '/api/v1/new-endpoint'
]
```

## Success Criteria

The Rails API implementation is considered compatible when:
- All endpoints return the same response structure
- Status codes match for all operations
- Job execution produces identical results
- Error handling is consistent
- WebSocket endpoints are available (even if implementation differs)

## Notes

- The tests normalize responses to handle minor formatting differences
- URLs in responses are compared by path only (ignoring host/port)
- Array ordering matters for entries but not for independent collections
- The test suite creates and cleans up test jobs automatically