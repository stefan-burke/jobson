#!/bin/bash

# Test script to verify Rails API compatibility with Java Jobson API

API_BASE="http://localhost:8080"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Testing Jobson Rails API Compatibility..."
echo "========================================="

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local expected_status=$3
    local description=$4
    local data=$5
    
    if [ -z "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method "$API_BASE$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method "$API_BASE$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓${NC} $description (HTTP $http_code)"
        return 0
    else
        echo -e "${RED}✗${NC} $description - Expected HTTP $expected_status, got $http_code"
        echo "  Response: $body"
        return 1
    fi
}

# Function to test JSON structure
test_json_field() {
    local endpoint=$1
    local field=$2
    local description=$3
    
    response=$(curl -s "$API_BASE$endpoint")
    
    if echo "$response" | python3 -c "import sys, json; data = json.load(sys.stdin); sys.exit(0 if '$field' in str(data) else 1)" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        echo "  Response: $response"
        return 1
    fi
}

# Test root endpoint
echo ""
echo "1. Testing Root Endpoints"
echo "--------------------------"
test_endpoint "GET" "/" 200 "Root endpoint returns 200"
test_json_field "/" "_links" "Root has _links field"

# Test V1 API root
echo ""
echo "2. Testing V1 API Root"
echo "----------------------"
test_endpoint "GET" "/api/v1" 200 "V1 root returns 200"
test_json_field "/api/v1" "_links" "V1 root has _links field"
test_json_field "/api/v1" "specs" "V1 root has specs link"
test_json_field "/api/v1" "jobs" "V1 root has jobs link"

# Test Job Specs endpoints
echo ""
echo "3. Testing Job Specs Endpoints"
echo "-------------------------------"
test_endpoint "GET" "/api/v1/specs" 200 "List specs returns 200"
test_json_field "/api/v1/specs" "specs" "Specs response has specs array"

# Check if echo spec exists
if curl -s "$API_BASE/api/v1/specs" | grep -q "echo"; then
    test_endpoint "GET" "/api/v1/specs/echo" 200 "Get echo spec returns 200"
    test_json_field "/api/v1/specs/echo" "name" "Echo spec has name field"
    test_json_field "/api/v1/specs/echo" "expectedInputs" "Echo spec has expectedInputs"
    test_json_field "/api/v1/specs/echo" "execution" "Echo spec has execution config"
fi

# Test Jobs endpoints
echo ""
echo "4. Testing Jobs Endpoints"
echo "--------------------------"
test_endpoint "GET" "/api/v1/jobs" 200 "List jobs returns 200"
test_json_field "/api/v1/jobs" "entries" "Jobs response has entries array"
test_json_field "/api/v1/jobs" "_links" "Jobs response has _links"

# Test job creation
echo ""
echo "5. Testing Job Creation"
echo "-----------------------"
job_data='{"name":"Test Job","spec":"echo","inputs":{"message":"API Test"}}'
response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/api/v1/jobs" \
    -H "Content-Type: application/json" \
    -d "$job_data")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "201" ]; then
    echo -e "${GREEN}✓${NC} Create job returns 201 Created"
    
    # Extract job ID
    job_id=$(echo "$body" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    
    if [ ! -z "$job_id" ]; then
        echo -e "${GREEN}✓${NC} Job created with ID: $job_id"
        
        # Test job-specific endpoints
        echo ""
        echo "6. Testing Job-Specific Endpoints"
        echo "----------------------------------"
        
        # Wait for job to process
        sleep 2
        
        test_endpoint "GET" "/api/v1/jobs/$job_id" 200 "Get job details returns 200"
        test_json_field "/api/v1/jobs/$job_id" "timestamps" "Job has timestamps"
        test_endpoint "GET" "/api/v1/jobs/$job_id/stdout" 200 "Get job stdout returns 200"
        test_endpoint "GET" "/api/v1/jobs/$job_id/stderr" 200 "Get job stderr returns 200"
        test_endpoint "GET" "/api/v1/jobs/$job_id/spec" 200 "Get job spec returns 200"
        test_endpoint "GET" "/api/v1/jobs/$job_id/inputs" 200 "Get job inputs returns 200"
        test_endpoint "GET" "/api/v1/jobs/$job_id/outputs" 200 "Get job outputs returns 200"
        
        # Test abort (should fail if job is already finished)
        test_endpoint "POST" "/api/v1/jobs/$job_id/abort" 400 "Abort finished job returns 400"
        
        # Test delete
        test_endpoint "DELETE" "/api/v1/jobs/$job_id" 204 "Delete job returns 204 No Content"
    else
        echo -e "${RED}✗${NC} Could not extract job ID from response"
    fi
else
    echo -e "${RED}✗${NC} Create job failed with HTTP $http_code"
    echo "  Response: $body"
fi

echo ""
echo "========================================="
echo "API Compatibility Test Complete"