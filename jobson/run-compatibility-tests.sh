#!/bin/bash

# Run compatibility tests against Rails backend
# This script has two modes:
# 1. With Java/Maven: Runs Java-based compatibility tests
# 2. Without Java/Maven: Falls back to Python-based tests

set -e

echo "Rails API Compatibility Test"
echo "============================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Check for required tools
check_dependencies() {
    local has_ruby=false
    local has_rails=false
    local has_bundle=false
    local has_java=false
    local has_maven=false
    local has_python=false
    
    echo "Checking dependencies..."
    
    if command -v ruby >/dev/null 2>&1; then
        has_ruby=true
        echo -e "  ${GREEN}✓${NC} Ruby: $(ruby --version | cut -d' ' -f2)"
    else
        echo -e "  ${RED}✗${NC} Ruby: Not found"
    fi
    
    if command -v rails >/dev/null 2>&1; then
        has_rails=true
        echo -e "  ${GREEN}✓${NC} Rails: $(rails --version)"
    else
        echo -e "  ${RED}✗${NC} Rails: Not found"
    fi
    
    if command -v bundle >/dev/null 2>&1; then
        has_bundle=true
        echo -e "  ${GREEN}✓${NC} Bundler: Found"
    else
        echo -e "  ${RED}✗${NC} Bundler: Not found"
    fi
    
    if command -v java >/dev/null 2>&1; then
        has_java=true
        echo -e "  ${GREEN}✓${NC} Java: Found"
    else
        echo -e "  ${YELLOW}⚠${NC} Java: Not found (will use Python tests)"
    fi
    
    if command -v mvn >/dev/null 2>&1; then
        has_maven=true
        echo -e "  ${GREEN}✓${NC} Maven: Found"
    else
        echo -e "  ${YELLOW}⚠${NC} Maven: Not found (will use Python tests)"
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        has_python=true
        echo -e "  ${GREEN}✓${NC} Python3: $(python3 --version)"
    else
        echo -e "  ${YELLOW}⚠${NC} Python3: Not found"
    fi
    
    echo ""
    
    # Check what we can run
    if ! $has_ruby || ! $has_rails; then
        echo -e "${RED}Error: Ruby and Rails are required to run the server${NC}"
        echo ""
        echo "To install dependencies:"
        echo "  Ubuntu/Debian: sudo apt-get install ruby-full"
        echo "  macOS: brew install ruby"
        echo "  Then: gem install rails bundler"
        exit 1
    fi
    
    if $has_java && $has_maven; then
        echo -e "${GREEN}Using Java/Maven for comprehensive tests${NC}"
        return 0
    elif $has_python; then
        echo -e "${YELLOW}Using Python for compatibility tests${NC}"
        return 1
    else
        echo -e "${RED}Error: Neither Java/Maven nor Python3 available for testing${NC}"
        echo ""
        echo "Install one of:"
        echo "  Java + Maven: sudo apt-get install default-jdk maven"
        echo "  Python3: sudo apt-get install python3"
        exit 1
    fi
}

# Start Rails server
start_rails_server() {
    echo "Starting Rails server on port 8080..."
    cd src-rails
    
    # Ensure dependencies are installed
    if [ ! -f Gemfile.lock ] || [ ! -d vendor/bundle ]; then
        echo "Installing Rails dependencies..."
        if command -v bundle >/dev/null 2>&1; then
            bundle install
        else
            echo -e "${RED}Bundler not found. Please install: gem install bundler${NC}"
            exit 1
        fi
    fi
    
    # Start server in background
    if command -v rails >/dev/null 2>&1; then
        rails server -b 0.0.0.0 -p 8080 -d
    else
        # Try bundle exec
        bundle exec rails server -b 0.0.0.0 -p 8080 -d
    fi
    
    # Wait for server to be ready
    echo "Waiting for server to start..."
    for i in {1..30}; do
        if curl -s http://localhost:8080/api/v1 > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Rails server is ready"
            cd ..
            return 0
        fi
        sleep 1
        echo -n "."
    done
    
    echo ""
    echo -e "${RED}✗${NC} Rails server failed to start"
    cd ..
    return 1
}

# Main execution
echo ""

# Check what testing framework we can use
if check_dependencies; then
    # Use Java/Maven tests
    
    # Start Rails server
    if ! start_rails_server; then
        echo "Failed to start Rails server"
        exit 1
    fi
    
    # Run the Java compatibility tests
    echo ""
    echo "Running Java-based compatibility tests..."
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
else
    # Use Python tests
    
    # Check if Python script exists
    if [ ! -f "run-compatibility-tests.py" ]; then
        echo -e "${RED}Python test script not found${NC}"
        echo "Expected: run-compatibility-tests.py"
        exit 1
    fi
    
    # Run Python tests (it will start the server itself)
    echo ""
    echo "Running Python-based compatibility tests..."
    echo "------------------------------"
    python3 run-compatibility-tests.py
    
    exit $?
fi