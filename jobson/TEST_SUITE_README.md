# Jobson API Compatibility Test Suite

## Overview

This directory contains a comprehensive test suite for validating API compatibility between Java and Rails implementations of the Jobson API. The test suite has been designed to work without requiring nix or specific language runtimes.

## Test Components

### 1. Core Test Scripts

- **`run-compatibility-tests.sh`** - Main test runner that automatically detects available tools
  - Falls back to Python tests if Java/Maven not available
  - Checks for Ruby/Rails and uses mock server if needed
  - Provides clear dependency information

- **`run-compatibility-tests.py`** - Python-based test runner
  - Works with Python 3 (widely available)
  - Can use either real Rails server or mock server
  - Includes 23 basic compatibility tests

- **`comprehensive-api-tests.py`** - Extended test suite
  - 46 comprehensive tests covering all endpoints
  - Tests error handling, security, edge cases
  - Organized by category for clear reporting

### 2. Mock Server

- **`mock-rails-server.py`** - Python mock implementation
  - Simulates Rails API for testing without Rails
  - Implements all core endpoints
  - Supports WebSocket endpoint detection

### 3. Comparison Tools

- **`compare-api-responses.rb`** - Ruby-based API comparison
  - Direct side-by-side comparison of Java and Rails
  - Normalizes responses (ignores IDs, timestamps)
  - Interactive testing of specific endpoints

## Test Coverage

### Categories Tested

1. **Core API** (3 tests)
   - Root endpoint HAL structure
   - API v1 links
   - Invalid version handling

2. **Specs** (6 tests)
   - List specs
   - Get specific spec
   - Spec field validation
   - Nonexistent spec handling
   - Spec href validation

3. **Jobs** (9 tests)
   - Create/Read/Delete operations
   - Job listing and pagination
   - Invalid job creation
   - Job lifecycle

4. **Job Endpoints** (5 tests)
   - Stdout/stderr retrieval
   - Input/spec access
   - Job abortion

5. **Pagination** (3 tests)
   - Page size limits
   - Page navigation
   - Total count reporting

6. **Users** (2 tests)
   - Current user endpoint
   - Guest access validation

7. **WebSockets** (3 tests)
   - Event streams
   - Live stdout/stderr updates

8. **Error Handling** (3 tests)
   - Invalid JSON
   - Missing content type
   - Unsupported methods

9. **Edge Cases** (5 tests)
   - Unicode support
   - Long names
   - Special characters
   - Empty values
   - Null handling

10. **Security** (3 tests)
    - Path traversal prevention
    - SQL injection handling
    - Script injection sanitization

11. **Content Negotiation** (2 tests)
    - Default JSON responses
    - Accept header respect

12. **Job Lifecycle** (2 tests)
    - Complete workflow
    - Concurrent job handling

## Test Results

Current test status with mock server:
- **Total Tests**: 46
- **Passing**: 41 (89%)
- **Failing**: 5 (11%)

Known issues (mock server limitations):
- Null value handling in inputs
- Invalid JSON parsing
- Method not allowed (405) vs Not Implemented (501)
- URL encoding for SQL injection tests
- Script injection response handling

## Usage

### Quick Start (No Dependencies)

```bash
# Using Python mock server (no Rails needed)
./run-compatibility-tests.sh
```

### With Rails Server

```bash
# Start Rails server
cd src-rails
rails server -p 8080 -d

# Run tests
cd ..
python3 run-compatibility-tests.py
```

### Comprehensive Testing

```bash
# Run extended test suite
python3 comprehensive-api-tests.py
```

### Specific Endpoint Testing

```bash
# Ruby comparison tool (requires both servers)
ruby compare-api-responses.rb /api/v1/specs

# Test all endpoints
ruby compare-api-responses.rb --all

# Test job lifecycle
ruby compare-api-responses.rb --lifecycle
```

## Installation Requirements

### Minimal (Mock Testing)
- Python 3.x

### Rails Testing
- Ruby 2.7+
- Rails 7.0+
- Bundler

### Full Comparison Testing
- All of the above plus:
- Java 8+
- Maven 3.x

## Adding New Tests

### Python Tests

Add to `comprehensive-api-tests.py`:

```python
@test("Test name", "Category")
def test_new_feature():
    status, body, _ = make_request("GET", "/api/v1/new-endpoint")
    assert_status(status, 200)
    assert_fields(body, ["required", "fields"])
    return True
```

### Comparison Tests

Add to `api_comparison_test.rb`:

```ruby
test "new endpoint returns same structure" do
  java_response = fetch_json(:java, "/api/v1/new-endpoint")
  rails_response = fetch_json(:rails, "/api/v1/new-endpoint")
  assert_api_responses_equal(java_response, rails_response, "New endpoint")
end
```

## CI/CD Integration

### GitHub Actions

```yaml
- name: Run API Compatibility Tests
  run: |
    cd jobson
    ./run-compatibility-tests.sh
```

### Docker

```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN chmod +x *.sh *.py
CMD ["./run-compatibility-tests.sh"]
```

## Troubleshooting

### Common Issues

1. **"Rails not found"**
   - Tests will automatically use Python mock server
   - Install Rails: `gem install rails bundler`

2. **"Connection refused"**
   - Server not running on expected port
   - Check: `curl http://localhost:8080/api/v1`

3. **"Some tests failed"**
   - Review specific failures in output
   - Mock server has known limitations (see above)

4. **"Python not found"**
   - Install Python 3: `apt-get install python3`

## Future Improvements

1. Add performance benchmarking tests
2. Test streaming responses
3. Add authentication/authorization tests
4. Test file upload/download endpoints
5. Add stress testing scenarios
6. Implement WebSocket protocol tests
7. Add GraphQL endpoint tests (if applicable)

## Contributing

To contribute new tests:

1. Add test to appropriate category
2. Follow existing test patterns
3. Ensure tests work with mock server
4. Document any new dependencies
5. Update this README with coverage changes

## License

Same as parent Jobson project