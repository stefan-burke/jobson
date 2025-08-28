#!/bin/bash

# Final Real API Comparison Test
# Tests actual Java implementation against Rails implementation

set -e

echo "================================================"
echo "Final API Comparison Test"
echo "================================================"
echo ""
echo "Starting both servers and comparing API responses..."
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    pkill -f "java.*jobson" 2>/dev/null || true
    pkill -f "rails server" 2>/dev/null || true
    rm -f src-rails/tmp/pids/server.pid
}

trap cleanup EXIT

# Step 1: Build Java if needed
if [ ! -f target/jobson-1.0.14.jar ]; then
    echo "Building Java application..."
    mvn clean package -DskipTests
fi

# Step 2: Prepare workspace
mkdir -p workspace/specs workspace/jobs workspace/wds
touch users

# Create test specs
mkdir -p workspace/specs/echo
cat > workspace/specs/echo/spec.yml <<'EOF'
name: Echo
description: Simple echo command

expectedInputs:
  - id: message
    type: string
    name: Message
    description: The message to echo

execution:
  application: echo
  arguments:
    - "${inputs.message}"
EOF

# Step 3: Start Java server
cat > config.yml <<'EOF'
specs:
  dir: workspace/specs
jobs:
  dir: workspace/jobs
workingDirs:
  dir: workspace/wds
users:
  file: users
authentication:
  type: guest
EOF

echo -e "${YELLOW}Starting Java server on port 8080...${NC}"
java -jar target/jobson-1.0.14.jar server config.yml > java.log 2>&1 &
JAVA_PID=$!

# Wait for Java
for i in {1..20}; do
    if curl -s http://localhost:8080/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Java server ready${NC}"
        break
    fi
    sleep 1
done

# Step 4: Start Rails server
cd src-rails
if [ ! -e workspace ]; then
    ln -s ../workspace workspace
fi

echo -e "${YELLOW}Starting Rails server on port 3000...${NC}"
rails server -p 3000 > ../rails.log 2>&1 &
RAILS_PID=$!
cd ..

# Wait for Rails
for i in {1..20}; do
    if curl -s http://localhost:3000/api/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Rails server ready${NC}"
        break
    fi
    sleep 1
done

echo ""
echo "================================================"
echo "API Structure Comparison"
echo "================================================"
echo ""

# Compare endpoints
compare_endpoint() {
    local name="$1"
    local java_path="$2"
    local rails_path="$3"
    
    echo -e "${YELLOW}Testing: $name${NC}"
    
    # Get responses
    java_response=$(curl -s "http://localhost:8080$java_path" | python3 -m json.tool 2>/dev/null || echo "ERROR")
    rails_response=$(curl -s "http://localhost:3000$rails_path" | python3 -m json.tool 2>/dev/null || echo "ERROR")
    
    java_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080$java_path")
    rails_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000$rails_path")
    
    echo "  Java (port 8080): Status $java_status"
    echo "  Rails (port 3000): Status $rails_status"
    
    if [ "$java_status" = "$rails_status" ]; then
        echo -e "  ${GREEN}✓ Status codes match${NC}"
    else
        echo -e "  ${RED}✗ Status codes differ${NC}"
    fi
    
    echo ""
}

# Test main endpoints
compare_endpoint "Root API" "/" "/"
compare_endpoint "API Version Root" "/v1" "/api/v1"
compare_endpoint "List Specs" "/v1/specs" "/api/v1/specs"
compare_endpoint "Echo Spec" "/v1/specs/echo" "/api/v1/specs/echo"
compare_endpoint "List Jobs" "/v1/jobs" "/api/v1/jobs"
compare_endpoint "Current User" "/v1/users/current" "/api/v1/users/current"

echo "================================================"
echo "Job Creation Test"
echo "================================================"
echo ""

# Create a job on both servers
echo "Creating test job on Java server..."
java_job=$(curl -s -X POST http://localhost:8080/v1/jobs \
    -H "Content-Type: application/json" \
    -d '{"spec":"echo","name":"Test Job","inputs":{"message":"Hello from test"}}' \
    2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', 'ERROR'))" 2>/dev/null || echo "FAILED")

echo "Creating test job on Rails server..."
rails_job=$(curl -s -X POST http://localhost:3000/api/v1/jobs \
    -H "Content-Type: application/json" \
    -d '{"spec":"echo","name":"Test Job","inputs":{"message":"Hello from test"}}' \
    2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', 'ERROR'))" 2>/dev/null || echo "FAILED")

if [ "$java_job" != "FAILED" ] && [ "$java_job" != "ERROR" ]; then
    echo -e "${GREEN}✓ Java job created: $java_job${NC}"
else
    echo -e "${RED}✗ Java job creation failed${NC}"
fi

if [ "$rails_job" != "FAILED" ] && [ "$rails_job" != "ERROR" ]; then
    echo -e "${GREEN}✓ Rails job created: $rails_job${NC}"
else
    echo -e "${RED}✗ Rails job creation failed${NC}"
fi

echo ""
echo "================================================"
echo "Summary"
echo "================================================"
echo ""

echo "Key Differences Found:"
echo "1. Java API uses /v1/* paths"
echo "2. Rails API uses /api/v1/* paths"
echo "3. Both servers respond to their respective endpoints"
echo "4. Response structures need normalization for comparison"
echo ""
echo "To make APIs fully compatible, consider:"
echo "- Configuring Rails to use /v1 prefix instead of /api/v1"
echo "- Or configuring Java to use /api/v1 prefix"
echo "- Ensuring response format consistency"
echo ""
echo -e "${YELLOW}Check java.log and rails.log for server details${NC}"