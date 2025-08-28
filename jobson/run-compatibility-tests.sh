#!/usr/bin/env nix-shell
#!nix-shell -i bash -p ruby_3_2 bundler maven curl libyaml

# Run compatibility tests against Rails backend

set -e
set -x  # Enable verbose command execution

# Set up clean gem environment for nix-shell
export GEM_HOME="$PWD/src-rails/.bundle"
export GEM_PATH="$GEM_HOME"
export PATH="$GEM_HOME/bin:$PATH"
export BUNDLE_PATH="$GEM_HOME"

echo "Rails API Compatibility Test"
echo "============================"
echo ""

# Check if we're in compare mode
if [ "$1" = "--compare" ]; then
    export JOBSON_TEST_MODE=compare
    echo "COMPARE MODE: Will compare Rails vs Java backends for exact output matching"
    echo ""
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Track which servers we started (for cleanup)
RAILS_STARTED=false
JAVA_STARTED=false

# Function to cleanup
cleanup() {
    echo "Cleaning up..."
    # Only kill Rails if we started it
    if [ "$RAILS_STARTED" = "true" ]; then
        if [ -f src-rails/tmp/pids/server.pid ]; then
            echo "Stopping Rails server we started..."
            kill $(cat src-rails/tmp/pids/server.pid) 2>/dev/null || true
            rm -f src-rails/tmp/pids/server.pid
        fi
    fi
    # Only kill Java if we started it in compare mode
    if [ "$JAVA_STARTED" = "true" ] && [ ! -z "$JAVA_PID" ]; then
        echo "Stopping Java server we started..."
        kill $JAVA_PID 2>/dev/null || true
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check if Rails server is already running on port 8081
echo "Checking for existing Rails server on port 8081..."
if curl -s http://localhost:8081/api/v1 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Rails server already running on port 8081"
else
    # Start Rails server
    echo "Starting Rails server on port 8081..."
    cd src-rails

    # Ensure dependencies are installed
    echo "Installing Ruby dependencies..."
    bundle install

    # Start server in background
    bundle exec rails server -b 0.0.0.0 -p 8081 -d

    RAILS_STARTED=true

    # Wait for server to be ready
    echo "Waiting for Rails server to start..."
    for i in {1..10}; do
        if curl -s http://localhost:8081/api/v1 > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Rails server is ready"
            break
        fi
        sleep 1
    done

    cd ..
fi

# Run the compatibility tests
echo ""
echo "Running compatibility tests..."
echo "------------------------------"
echo ""

if [ "$JOBSON_TEST_MODE" = "compare" ]; then
    echo "Tests to run (exact comparison mode):"
    echo "  1. testRootEndpoint - Compare root API endpoint structure exactly"
    echo "  2. testV1RootEndpoint - Compare /api/v1 endpoint exactly"
    echo "  3. testSpecsEndpoint - Compare job specs listing exactly"
    echo "  4. testJobsEndpoint - Compare jobs listing exactly"
    echo "  5. testCreateAndGetJob - Compare job creation/retrieval exactly"
    echo ""
    echo "Note: IDs and timestamps are excluded from comparison"
    echo ""
    
    # Check if Java server is already running on port 8080
    echo "Checking for existing Java server on port 8080..."
    if curl -s http://localhost:8080/api/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Java server already running on port 8080"
    else
        # Start Java server if in compare mode
        echo "Starting Java server on port 8080..."
        
        # Build Java backend if needed
        if [ ! -f target/jobson*.jar ]; then
            mvn clean package -DskipTests
        fi
        
        # Create minimal config
        mkdir -p /tmp/jobson-jobs
        mkdir -p /tmp/jobson-wds
        
        # Use Rails specs for consistency between both servers
        mkdir -p specs
        cp -r src-rails/workspace/specs/* specs/
        
        # Create empty users file
        touch /tmp/jobson-users
        
        cat > test-config.yml <<EOF
server:
  applicationConnectors:
    - type: http
      port: 8080
  adminConnectors:
    - type: http
      port: 8082

jobs:
  dir: /tmp/jobson-jobs

specs:
  dir: specs

workingDirs:
  dir: /tmp/jobson-wds

users:
  file: /tmp/jobson-users

authentication:
  type: guest
EOF
        
        # Start Java server in background
        # Use maven to run with proper classpath
        mvn exec:java -Dexec.mainClass="com.github.jobson.App" -Dexec.args="serve test-config.yml" &
        JAVA_PID=$!
        
        JAVA_STARTED=true
        
        # Wait for Java server
        echo "Waiting for Java server to start..."
        for i in {1..20}; do
            if curl -s http://localhost:8080/api/v1 > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} Java server is ready"
                break
            fi
            sleep 1
        done
    fi
else
    echo "Tests to run:"
    echo "  1. testRootEndpoint - Verifies root API endpoint structure"
    echo "  2. testV1RootEndpoint - Verifies /api/v1 endpoint"
    echo "  3. testSpecsEndpoint - Verifies job specs listing"
    echo "  4. testJobsEndpoint - Verifies jobs listing"
    echo "  5. testCreateAndGetJob - Creates a job and retrieves it"
fi

echo ""
echo "Executing tests..."
echo ""

# Run Maven with more verbose output
mvn test -Dtest=RailsCompatibilityTest -DshowSuccess=true -DreportFormat=plain

TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
    echo ""
    if [ "$JOBSON_TEST_MODE" = "compare" ]; then
        echo -e "${GREEN}✓ All exact compatibility tests passed!${NC}"
        echo "The Rails and Java APIs produce identical output (except IDs/timestamps)."
    else
        echo -e "${GREEN}✓ All compatibility tests passed!${NC}"
        echo "The Rails API is compatible with the Java API."
    fi
else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    echo "Check the output above for details."
fi

exit $TEST_RESULT
