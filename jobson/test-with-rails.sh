#!/bin/bash

# Script to test the Java test suite against the Rails backend
# This demonstrates that the Rails API is compatible with the Java version

echo "Starting Rails backend for Java tests..."

# Kill any existing Rails server
if [ -f src-rails/tmp/pids/server.pid ]; then
    kill $(cat src-rails/tmp/pids/server.pid) 2>/dev/null || true
    rm -f src-rails/tmp/pids/server.pid
fi

# Set up Rails environment
cd src-rails
export RAILS_ENV=test

# Install dependencies if needed
if [ ! -d "vendor/bundle" ]; then
    echo "Installing Rails dependencies..."
    bundle install --path vendor/bundle --quiet
fi

# Start Rails server on port 8080 (same as Java default)
echo "Starting Rails server on port 8080..."
bundle exec rails server -b 0.0.0.0 -p 8080 -d

# Wait for server to start
sleep 5

cd ..

echo "Rails server started. Running Java tests..."
echo "========================================="

# Run the Java tests
# Note: These tests expect the API to be running on localhost:8080
# Some tests will fail because they expect Java-specific behaviors,
# but basic API compatibility tests should pass

mvn test -Dtest=TestJobsAPI,TestJobSpecsAPI,TestRootAPI

# Capture test result
TEST_RESULT=$?

# Stop Rails server
echo ""
echo "Stopping Rails server..."
kill $(cat src-rails/tmp/pids/server.pid) 2>/dev/null || true
rm -f src-rails/tmp/pids/server.pid

echo "Test completed with exit code: $TEST_RESULT"
exit $TEST_RESULT