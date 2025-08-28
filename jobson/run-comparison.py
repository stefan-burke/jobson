#!/usr/bin/env python3

import json
import urllib.request
import urllib.error
import sys
import time
from typing import Dict, Any, Tuple, List

# Configuration
JAVA_URL = "http://localhost:8080"
RAILS_URL = "http://localhost:3000"

# Colors
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
NC = '\033[0m'

# Fields to ignore when comparing
IGNORE_FIELDS = {'id', 'jobId', 'created_at', 'updated_at', 'timestamps'}

def make_request(base_url: str, method: str, path: str, data: Dict = None) -> Tuple[int, Any]:
    """Make HTTP request and return status code and response"""
    url = f"{base_url}{path}"
    
    headers = {'Accept': 'application/json'}
    
    if data is not None:
        data_bytes = json.dumps(data).encode('utf-8')
        headers['Content-Type'] = 'application/json'
        request = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
    else:
        request = urllib.request.Request(url, headers=headers, method=method)
    
    try:
        response = urllib.request.urlopen(request)
        status = response.status
        body = response.read().decode('utf-8')
        
        try:
            body = json.loads(body) if body else None
        except:
            pass  # Keep as string
            
        return status, body
        
    except urllib.error.HTTPError as e:
        status = e.code
        body = e.read().decode('utf-8')
        try:
            body = json.loads(body) if body else None
        except:
            pass
        return status, body

def normalize_response(data: Any) -> Any:
    """Remove fields that differ between implementations"""
    if isinstance(data, dict):
        normalized = {}
        for key, value in data.items():
            if key not in IGNORE_FIELDS:
                # Normalize URLs to just paths
                if isinstance(value, str) and 'http' in value:
                    value = value.replace('http://localhost:8081', '').replace('http://localhost:8080', '')
                normalized[key] = normalize_response(value)
        return normalized
    elif isinstance(data, list):
        return [normalize_response(item) for item in data]
    else:
        return data

def compare_responses(java_response: Any, rails_response: Any, path: List[str] = []) -> List[str]:
    """Deep compare two responses and return differences"""
    differences = []
    
    if type(java_response) != type(rails_response):
        differences.append(f"Type mismatch at {'.'.join(path)}: Java={type(java_response).__name__}, Rails={type(rails_response).__name__}")
        return differences
    
    if isinstance(java_response, dict):
        java_keys = set(java_response.keys())
        rails_keys = set(rails_response.keys())
        
        missing_in_rails = java_keys - rails_keys
        missing_in_java = rails_keys - java_keys
        
        if missing_in_rails:
            differences.append(f"Missing in Rails at {'.'.join(path)}: {', '.join(missing_in_rails)}")
        
        if missing_in_java:
            differences.append(f"Missing in Java at {'.'.join(path)}: {', '.join(missing_in_java)}")
        
        for key in java_keys & rails_keys:
            differences.extend(compare_responses(java_response[key], rails_response[key], path + [key]))
    
    elif isinstance(java_response, list):
        if len(java_response) != len(rails_response):
            differences.append(f"Array length at {'.'.join(path)}: Java={len(java_response)}, Rails={len(rails_response)}")
        else:
            for i, (j_item, r_item) in enumerate(zip(java_response, rails_response)):
                differences.extend(compare_responses(j_item, r_item, path + [f"[{i}]"]))
    
    else:
        if java_response != rails_response:
            differences.append(f"Value at {'.'.join(path)}: Java={java_response}, Rails={rails_response}")
    
    return differences

def test_endpoint(name: str, method: str, path: str, data: Dict = None) -> bool:
    """Test an endpoint on both servers and compare"""
    print(f"\nTesting: {method} {path}")
    print("-" * 40)
    
    # Make requests to both servers
    java_status, java_body = make_request(JAVA_URL, method, path, data)
    rails_status, rails_body = make_request(RAILS_URL, method, path, data)
    
    # Compare status codes
    if java_status != rails_status:
        print(f"{RED}✗{NC} Status mismatch: Java={java_status}, Rails={rails_status}")
        return False
    else:
        print(f"{GREEN}✓{NC} Status codes match: {java_status}")
    
    # Compare responses
    if java_body is not None and rails_body is not None:
        java_normalized = normalize_response(java_body)
        rails_normalized = normalize_response(rails_body)
        
        differences = compare_responses(java_normalized, rails_normalized)
        
        if differences:
            print(f"{RED}✗{NC} Response differences:")
            for diff in differences[:5]:  # Show first 5 differences
                print(f"  - {diff}")
            return False
        else:
            print(f"{GREEN}✓{NC} Responses match (excluding IDs/timestamps)")
    
    print(f"{GREEN}✓{NC} {name}")
    return True

def run_tests():
    """Run all comparison tests"""
    passed = 0
    failed = 0
    
    tests = [
        ("Root endpoint", "GET", "/"),
        ("API v1 root", "GET", "/api/v1"),
        ("List specs", "GET", "/api/v1/specs"),
        ("Get echo spec", "GET", "/api/v1/specs/echo"),
        ("Get sleep spec", "GET", "/api/v1/specs/sleep"),
        ("List jobs (empty)", "GET", "/api/v1/jobs"),
        ("Current user", "GET", "/api/v1/users/current"),
    ]
    
    # Basic endpoint tests
    print(f"\n{YELLOW}Basic Endpoint Comparison{NC}")
    print("=" * 40)
    
    for name, method, path in tests:
        if test_endpoint(name, method, path):
            passed += 1
        else:
            failed += 1
    
    # Job lifecycle test
    print(f"\n{YELLOW}Job Lifecycle Comparison{NC}")
    print("=" * 40)
    
    job_data = {
        "spec": "echo",
        "name": "Comparison Test",
        "inputs": {"message": "Testing API compatibility"}
    }
    
    # Create jobs on both servers
    print("\nCreating test job on both servers...")
    java_status, java_job = make_request(JAVA_URL, "POST", "/api/v1/jobs", job_data)
    rails_status, rails_job = make_request(RAILS_URL, "POST", "/api/v1/jobs", job_data)
    
    if java_status == 200 and rails_status == 200:
        print(f"{GREEN}✓{NC} Jobs created successfully")
        passed += 1
        
        # Compare job creation responses (normalized)
        java_normalized = normalize_response(java_job)
        rails_normalized = normalize_response(rails_job)
        differences = compare_responses(java_normalized, rails_normalized)
        
        if differences:
            print(f"{YELLOW}⚠{NC} Job creation response differences:")
            for diff in differences[:3]:
                print(f"  - {diff}")
            failed += 1
        else:
            print(f"{GREEN}✓{NC} Job creation responses match")
            passed += 1
        
        # Test job endpoints
        java_id = java_job['id']
        rails_id = rails_job['id']
        
        job_endpoints = [
            ("Job details", f"/api/v1/jobs/{{}}", "GET"),
            ("Job inputs", f"/api/v1/jobs/{{}}/inputs", "GET"),
            ("Job spec", f"/api/v1/jobs/{{}}/spec", "GET"),
        ]
        
        for name, path_template, method in job_endpoints:
            print(f"\nTesting: {name}")
            java_status, java_resp = make_request(JAVA_URL, method, path_template.format(java_id))
            rails_status, rails_resp = make_request(RAILS_URL, method, path_template.format(rails_id))
            
            if java_status == rails_status:
                java_norm = normalize_response(java_resp)
                rails_norm = normalize_response(rails_resp)
                diffs = compare_responses(java_norm, rails_norm)
                
                if not diffs:
                    print(f"{GREEN}✓{NC} {name} responses match")
                    passed += 1
                else:
                    print(f"{RED}✗{NC} {name} differences:")
                    for diff in diffs[:3]:
                        print(f"  - {diff}")
                    failed += 1
            else:
                print(f"{RED}✗{NC} Status mismatch: Java={java_status}, Rails={rails_status}")
                failed += 1
        
        # Clean up
        make_request(JAVA_URL, "DELETE", f"/api/v1/jobs/{java_id}")
        make_request(RAILS_URL, "DELETE", f"/api/v1/jobs/{rails_id}")
        print(f"\n{GREEN}✓{NC} Test jobs cleaned up")
        
    else:
        print(f"{RED}✗{NC} Failed to create test jobs")
        failed += 1
    
    # Pagination test
    print(f"\n{YELLOW}Pagination Comparison{NC}")
    print("=" * 40)
    
    if test_endpoint("Jobs with pagination", "GET", "/api/v1/jobs?page-size=5&page=0"):
        passed += 1
    else:
        failed += 1
    
    # Summary
    print("\n" + "=" * 50)
    print(f"Test Results")
    print("=" * 50)
    print(f"Passed: {GREEN}{passed}{NC}")
    print(f"Failed: {RED}{failed}{NC}")
    
    if failed == 0:
        print(f"\n{GREEN}✓ All tests passed! APIs are compatible.{NC}")
        return 0
    else:
        print(f"\n{RED}✗ Some tests failed. Review differences above.{NC}")
        return 1

if __name__ == "__main__":
    # Verify servers are running
    try:
        make_request(JAVA_URL, "GET", "/api/v1")
        print(f"{GREEN}✓{NC} Java server responding")
    except:
        print(f"{RED}✗{NC} Java server not responding at {JAVA_URL}")
        sys.exit(1)
    
    try:
        make_request(RAILS_URL, "GET", "/api/v1")
        print(f"{GREEN}✓{NC} Rails server responding")
    except:
        print(f"{RED}✗{NC} Rails server not responding at {RAILS_URL}")
        sys.exit(1)
    
    sys.exit(run_tests())
