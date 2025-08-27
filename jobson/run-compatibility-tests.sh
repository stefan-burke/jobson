#!/bin/bash

# Run compatibility tests against Rails backend

set -e

echo "Rails API Compatibility Test"
echo "============================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Function to cleanup
cleanup() {
    echo "Cleaning up..."
    if [ -f src-rails/tmp/pids/server.pid ]; then
        kill $(cat src-rails/tmp/pids/server.pid) 2>/dev/null || true
        rm -f src-rails/tmp/pids/server.pid
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Kill any existing Rails server
cleanup

# Start Rails server
echo "Starting Rails server on port 8080..."
cd src-rails

# Ensure dependencies are installed
if [ ! -f Gemfile.lock ]; then
    bundle install
fi

# Start server in background
rails server -b 0.0.0.0 -p 8080 -d

# Wait for server to be ready
echo "Waiting for server to start..."
for i in {1..10}; do
    if curl -s http://localhost:8080/api/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Rails server is ready"
        break
    fi
    sleep 1
done

cd ..

# Run the compatibility tests
echo ""
echo "Running compatibility tests..."
echo "------------------------------"
mvn test -Dtest=RailsCompatibilityTest

TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All compatibility tests passed!${NC}"
    echo "The Rails API is compatible with the Java API."
else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    echo "Check the output above for details."
fi

exit $TEST_RESULT