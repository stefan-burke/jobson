#!/bin/bash

# Script to run API comparison tests between Java and Rails implementations
# This starts both servers and runs comprehensive comparison tests

set -e

# Configuration
JAVA_PORT=8081
RAILS_PORT=3000
JAVA_JAR="target/jobson-*.jar"
RAILS_DIR="src-rails"
TEST_TIMEOUT=60

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# PIDs for cleanup
JAVA_PID=""
RAILS_PID=""

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Kill Java server
    if [ -n "$JAVA_PID" ]; then
        echo "Stopping Java server (PID: $JAVA_PID)..."
        kill $JAVA_PID 2>/dev/null || true
    fi
    
    # Kill Rails server
    if [ -n "$RAILS_PID" ]; then
        echo "Stopping Rails server (PID: $RAILS_PID)..."
        kill $RAILS_PID 2>/dev/null || true
    fi
    
    # Clean up Rails server pid file
    if [ -f "$RAILS_DIR/tmp/pids/server.pid" ]; then
        rm -f "$RAILS_DIR/tmp/pids/server.pid"
    fi
    
    # Wait a moment for ports to be released
    sleep 2
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

echo "========================================="
echo "API Comparison Test Suite"
echo "========================================="
echo ""
echo "This test will compare the Java and Rails"
echo "implementations of the Jobson API to ensure"
echo "they return identical responses."
echo ""

# Step 1: Build Java application if needed
echo -e "${YELLOW}Step 1: Building Java application...${NC}"
if ! ls $JAVA_JAR 1> /dev/null 2>&1; then
    echo "Building Java JAR..."
    mvn clean package -DskipTests
else
    echo "Java JAR already exists"
fi

# Step 2: Prepare workspace directory (needed by both servers)
echo -e "${YELLOW}Step 2: Preparing workspace...${NC}"
if [ ! -d "workspace" ]; then
    echo "Creating workspace directory..."
    mkdir -p workspace/specs
    mkdir -p workspace/jobs
    mkdir -p workspace/wds
fi

# Copy specs to workspace if not present
if [ ! -d "workspace/specs/echo" ]; then
    echo "Copying example specs..."
    cp -r src/test/resources/fixtures/specs/* workspace/specs/ 2>/dev/null || true
    
    # Create simple echo spec if fixtures don't exist
    if [ ! -d "workspace/specs/echo" ]; then
        mkdir -p workspace/specs/echo
        cat > workspace/specs/echo/spec.yml <<EOF
name: Echo
description: Simple echo command that prints input to stdout

expectedInputs:
  - id: message
    type: string
    name: Message
    description: The message to echo
    default: Hello, World!

execution:
  application: echo
  arguments:
    - "\${inputs.message}"

expectedOutputs: []
EOF
    fi
fi

# Step 3: Start Java server
echo -e "${YELLOW}Step 3: Starting Java server on port $JAVA_PORT...${NC}"

# Create config file for Java server if needed
if [ ! -f "config.yml" ]; then
    cat > config.yml <<EOF
jobSpec:
  dir: workspace/specs
jobs:
  dir: workspace/jobs
workingDirs:
  dir: workspace/wds
server:
  applicationConnectors:
    - type: http
      port: $JAVA_PORT
  adminConnectors:
    - type: http
      port: 8082
EOF
fi

# Start Java server in background
java -jar $JAVA_JAR server config.yml > java-server.log 2>&1 &
JAVA_PID=$!

echo "Java server starting (PID: $JAVA_PID)..."

# Wait for Java server to be ready
echo "Waiting for Java server to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:$JAVA_PORT/api/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Java server is ready on port $JAVA_PORT"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Verify Java server is actually responding
if ! curl -s http://localhost:$JAVA_PORT/api/v1 > /dev/null 2>&1; then
    echo -e "${RED}✗${NC} Java server failed to start"
    echo "Check java-server.log for details"
    exit 1
fi

# Step 4: Start Rails server
echo -e "${YELLOW}Step 4: Starting Rails server on port $RAILS_PORT...${NC}"

cd $RAILS_DIR

# Install dependencies if needed
if [ ! -f "Gemfile.lock" ] || [ ! -d "vendor/bundle" ]; then
    echo "Installing Rails dependencies..."
    bundle install
fi

# Create specs symlink if needed (Rails looks in workspace/specs)
if [ ! -L "workspace" ] && [ ! -d "workspace" ]; then
    ln -s ../workspace workspace
fi

# Start Rails server in background
RAILS_ENV=test rails server -b 0.0.0.0 -p $RAILS_PORT > ../rails-server.log 2>&1 &
RAILS_PID=$!

cd ..

echo "Rails server starting (PID: $RAILS_PID)..."

# Wait for Rails server to be ready
echo "Waiting for Rails server to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:$RAILS_PORT/api/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Rails server is ready on port $RAILS_PORT"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Verify Rails server is actually responding
if ! curl -s http://localhost:$RAILS_PORT/api/v1 > /dev/null 2>&1; then
    echo -e "${RED}✗${NC} Rails server failed to start"
    echo "Check rails-server.log for details"
    exit 1
fi

# Step 5: Run comparison tests
echo ""
echo -e "${YELLOW}Step 5: Running API comparison tests...${NC}"
echo "========================================="

# Set environment variables for test
export JAVA_API_URL="http://localhost:$JAVA_PORT"
export RAILS_API_URL="http://localhost:$RAILS_PORT"

# Run the Rails test suite
cd $RAILS_DIR
RAILS_ENV=test rails test test/api_comparison_test.rb --verbose

TEST_RESULT=$?

cd ..

# Step 6: Report results
echo ""
echo "========================================="

if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ All API comparison tests passed!${NC}"
    echo ""
    echo "The Rails API is fully compatible with the Java API."
    echo "Both implementations return identical responses."
else
    echo -e "${RED}✗ Some comparison tests failed${NC}"
    echo ""
    echo "Check the test output above for details on which"
    echo "endpoints are returning different responses."
    echo ""
    echo "Server logs are available at:"
    echo "  - java-server.log"
    echo "  - rails-server.log"
fi

echo "========================================="

exit $TEST_RESULT