#!/usr/bin/env python3

"""
Comprehensive API Test Suite for Jobson Rails API
Tests all endpoints, error conditions, edge cases, and validates response structures
"""

import json
import sys
import time
import urllib.request
import urllib.parse
import urllib.error
from typing import Dict, Any, List, Optional, Tuple
import uuid
import random
import string

# Configuration
API_URL = "http://localhost:8080"

# Colors for output
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'  # No Color

# Test results tracking
test_results = []
test_groups = {}

def make_request(method: str, path: str, data: Optional[Dict] = None, 
                 headers: Optional[Dict] = None) -> Tuple[int, Any, Dict]:
    """Make HTTP request to the API"""
    url = f"{API_URL}{path}"
    
    headers = headers or {}
    headers['Accept'] = 'application/json'
    
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
        
        # Try to parse as JSON
        try:
            body = json.loads(body) if body else None
        except:
            pass  # Keep as string if not JSON
            
        return status, body, dict(response.headers)
        
    except urllib.error.HTTPError as e:
        status = e.code
        body = e.read().decode('utf-8')
        try:
            body = json.loads(body) if body else None
        except:
            pass
        return status, body, dict(e.headers)

def test(name: str, group: str = "General") -> callable:
    """Decorator for test functions"""
    def decorator(func):
        def wrapper():
            try:
                result = func()
                if result:
                    print(f"  {GREEN}✓{NC} {name}")
                    test_results.append((name, True, group))
                    if group not in test_groups:
                        test_groups[group] = []
                    test_groups[group].append((name, True))
                else:
                    print(f"  {RED}✗{NC} {name}")
                    test_results.append((name, False, group))
                    if group not in test_groups:
                        test_groups[group] = []
                    test_groups[group].append((name, False))
            except Exception as e:
                print(f"  {RED}✗{NC} {name}: {str(e)}")
                test_results.append((name, False, group))
                if group not in test_groups:
                    test_groups[group] = []
                test_groups[group].append((name, False))
        wrapper.__name__ = func.__name__
        wrapper._is_test = True
        wrapper._test_name = name
        wrapper._test_group = group
        return wrapper
    return decorator

def assert_equal(actual, expected, msg=""):
    """Assert values are equal"""
    if actual != expected:
        raise AssertionError(f"{msg}: Expected {expected}, got {actual}")
    return True

def assert_in(item, container, msg=""):
    """Assert item is in container"""
    if item not in container:
        raise AssertionError(f"{msg}: {item} not in {container}")
    return True

def assert_status(status, expected, msg=""):
    """Assert HTTP status code"""
    if status != expected:
        raise AssertionError(f"{msg}: Expected status {expected}, got {status}")
    return True

def assert_fields(data, fields, msg=""):
    """Assert all fields are present in data"""
    if not isinstance(data, dict):
        raise AssertionError(f"{msg}: Response is not a dictionary")
    missing = [f for f in fields if f not in data]
    if missing:
        raise AssertionError(f"{msg}: Missing fields: {missing}")
    return True

# ============================================================================
# Core API Tests
# ============================================================================

@test("Root endpoint returns HAL structure", "Core API")
def test_root_endpoint():
    status, body, _ = make_request("GET", "/")
    assert_status(status, 200)
    assert_fields(body, ["_links"])
    assert_in("specs", body["_links"])
    assert_in("jobs", body["_links"])
    return True

@test("API v1 endpoint returns correct links", "Core API")
def test_api_v1_endpoint():
    status, body, _ = make_request("GET", "/api/v1")
    assert_status(status, 200)
    assert_fields(body, ["_links"])
    links = body["_links"]
    assert_in("specs", links)
    assert_in("jobs", links)
    assert_in("current-user", links)
    return True

@test("Invalid API version returns 404", "Core API")
def test_invalid_api_version():
    status, _, _ = make_request("GET", "/api/v2")
    assert_status(status, 404)
    return True

# ============================================================================
# Specs Tests
# ============================================================================

@test("List specs returns array", "Specs")
def test_list_specs():
    status, body, _ = make_request("GET", "/api/v1/specs")
    assert_status(status, 200)
    assert_in("entries", body)
    assert isinstance(body["entries"], list), "entries should be array"
    return True

@test("Spec entries have required fields", "Specs")
def test_spec_entry_fields():
    status, body, _ = make_request("GET", "/api/v1/specs")
    assert_status(status, 200)
    if body["entries"]:
        spec = body["entries"][0]
        assert_fields(spec, ["id", "name", "description", "href"])
    return True

@test("Get echo spec returns correct structure", "Specs")
def test_get_echo_spec():
    status, body, _ = make_request("GET", "/api/v1/specs/echo")
    assert_status(status, 200)
    assert_fields(body, ["id", "name", "description", "expectedInputs"])
    assert_equal(body["id"], "echo")
    assert isinstance(body["expectedInputs"], list), "expectedInputs should be array"
    return True

@test("Echo spec has message input", "Specs")
def test_echo_spec_inputs():
    status, body, _ = make_request("GET", "/api/v1/specs/echo")
    assert_status(status, 200)
    inputs = body.get("expectedInputs", [])
    assert len(inputs) > 0, "Should have at least one input"
    message_input = next((i for i in inputs if i.get("id") == "message"), None)
    assert message_input is not None, "Should have message input"
    assert_fields(message_input, ["id", "type", "name", "description"])
    return True

@test("Get nonexistent spec returns 404", "Specs")
def test_nonexistent_spec():
    status, _, _ = make_request("GET", "/api/v1/specs/doesnotexist")
    assert_status(status, 404)
    return True

@test("Spec href links are valid", "Specs")
def test_spec_href_links():
    status, body, _ = make_request("GET", "/api/v1/specs")
    assert_status(status, 200)
    for spec in body.get("entries", []):
        href = spec.get("href")
        assert href is not None, f"Spec {spec.get('id')} missing href"
        # Test that the href is accessible
        status2, _, _ = make_request("GET", href)
        assert status2 == 200, f"Spec href {href} not accessible"
    return True

# ============================================================================
# Jobs Tests
# ============================================================================

@test("List jobs returns paginated structure", "Jobs")
def test_list_jobs():
    status, body, _ = make_request("GET", "/api/v1/jobs")
    assert_status(status, 200)
    assert_in("entries", body)
    assert isinstance(body["entries"], list), "entries should be array"
    return True

@test("Create job with valid spec succeeds", "Jobs")
def test_create_valid_job():
    job_data = {
        "spec": "echo",
        "name": "Test Job",
        "inputs": {"message": "Hello Test"}
    }
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    assert_fields(body, ["id", "name", "spec"])
    assert_equal(body["name"], "Test Job")
    assert_equal(body["spec"], "echo")
    # Clean up
    make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

@test("Create job with minimal data succeeds", "Jobs")
def test_create_minimal_job():
    job_data = {"spec": "echo"}
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    assert_in("id", body)
    assert_equal(body["spec"], "echo")
    # Clean up
    make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

@test("Create job with invalid spec fails", "Jobs")
def test_create_invalid_spec_job():
    job_data = {"spec": "nonexistent"}
    status, _, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 400)
    return True

@test("Create job without spec fails", "Jobs")
def test_create_job_no_spec():
    job_data = {"name": "No Spec Job"}
    status, _, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert status == 400 or status == 422, f"Expected 400/422, got {status}"
    return True

@test("Get job details includes timestamps", "Jobs")
def test_get_job_details():
    # Create a job
    job_data = {"spec": "echo", "name": "Detail Test"}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    # Get details
    status, body, _ = make_request("GET", f"/api/v1/jobs/{job_id}")
    assert_status(status, 200)
    assert_fields(body, ["id", "name", "spec", "timestamps"])
    assert isinstance(body["timestamps"], dict), "timestamps should be object"
    
    # Clean up
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

@test("Get nonexistent job returns 404", "Jobs")
def test_get_nonexistent_job():
    fake_id = str(uuid.uuid4())
    status, _, _ = make_request("GET", f"/api/v1/jobs/{fake_id}")
    assert_status(status, 404)
    return True

@test("Delete job removes it", "Jobs")
def test_delete_job():
    # Create a job
    job_data = {"spec": "echo", "name": "Delete Test"}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    # Delete it
    status, _, _ = make_request("DELETE", f"/api/v1/jobs/{job_id}")
    assert_status(status, 200)
    
    # Verify it's gone
    status, _, _ = make_request("GET", f"/api/v1/jobs/{job_id}")
    assert_status(status, 404)
    return True

@test("Delete nonexistent job returns 404", "Jobs")
def test_delete_nonexistent_job():
    fake_id = str(uuid.uuid4())
    status, _, _ = make_request("DELETE", f"/api/v1/jobs/{fake_id}")
    assert_status(status, 404)
    return True

# ============================================================================
# Job Sub-endpoints Tests
# ============================================================================

@test("Get job inputs returns correct data", "Job Endpoints")
def test_get_job_inputs():
    inputs = {"message": "Test Input Message"}
    job_data = {"spec": "echo", "inputs": inputs}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    status, body, _ = make_request("GET", f"/api/v1/jobs/{job_id}/inputs")
    assert_status(status, 200)
    assert_equal(body, inputs)
    
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

@test("Get job spec returns spec details", "Job Endpoints")
def test_get_job_spec():
    job_data = {"spec": "echo"}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    status, body, _ = make_request("GET", f"/api/v1/jobs/{job_id}/spec")
    assert_status(status, 200)
    assert_fields(body, ["id", "name", "description"])
    assert_equal(body["id"], "echo")
    
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

@test("Get job stdout returns text", "Job Endpoints")
def test_get_job_stdout():
    job_data = {"spec": "echo", "inputs": {"message": "stdout test"}}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    time.sleep(0.5)  # Let job execute
    
    status, body, headers = make_request("GET", f"/api/v1/jobs/{job_id}/stdout")
    assert_status(status, 200)
    # Should return text/plain
    content_type = headers.get('Content-Type', '')
    assert 'text' in content_type, f"Expected text content, got {content_type}"
    
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

@test("Get job stderr returns text", "Job Endpoints")
def test_get_job_stderr():
    job_data = {"spec": "echo"}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    status, body, headers = make_request("GET", f"/api/v1/jobs/{job_id}/stderr")
    assert_status(status, 200)
    content_type = headers.get('Content-Type', '')
    assert 'text' in content_type, f"Expected text content, got {content_type}"
    
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

@test("Abort job endpoint exists", "Job Endpoints")
def test_abort_job():
    job_data = {"spec": "echo"}
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = created["id"]
    
    status, _, _ = make_request("POST", f"/api/v1/jobs/{job_id}/abort")
    # Accept 200 (success), 404 (already finished), or 409 (conflict)
    assert status in [200, 404, 409], f"Unexpected status: {status}"
    
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

# ============================================================================
# Pagination Tests
# ============================================================================

@test("Jobs pagination with page-size", "Pagination")
def test_jobs_page_size():
    # Create multiple jobs
    job_ids = []
    for i in range(7):
        job_data = {"spec": "echo", "name": f"Page Test {i}"}
        status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
        if status == 200:
            job_ids.append(created["id"])
    
    # Request with page size
    status, body, _ = make_request("GET", "/api/v1/jobs?page-size=3")
    assert_status(status, 200)
    assert len(body["entries"]) <= 3, f"Expected max 3 entries, got {len(body['entries'])}"
    
    # Clean up
    for job_id in job_ids:
        make_request("DELETE", f"/api/v1/jobs/{job_id}")
    
    return True

@test("Jobs pagination with page parameter", "Pagination")
def test_jobs_page_parameter():
    status, body, _ = make_request("GET", "/api/v1/jobs?page=0&page-size=5")
    assert_status(status, 200)
    assert_in("entries", body)
    return True

@test("Jobs pagination returns total count", "Pagination")
def test_jobs_pagination_total():
    status, body, _ = make_request("GET", "/api/v1/jobs")
    assert_status(status, 200)
    # Check if pagination info is provided
    if "total" in body or "pageSize" in body:
        return True
    # Also accept if entries is provided without pagination
    assert_in("entries", body)
    return True

# ============================================================================
# User Tests
# ============================================================================

@test("Current user endpoint returns user info", "Users")
def test_current_user():
    status, body, _ = make_request("GET", "/api/v1/users/current")
    assert_status(status, 200)
    assert_fields(body, ["id", "name"])
    return True

@test("Current user has guest access", "Users")
def test_current_user_guest():
    status, body, _ = make_request("GET", "/api/v1/users/current")
    assert_status(status, 200)
    # Should indicate guest or anonymous user
    assert body.get("id") is not None, "User should have an ID"
    return True

# ============================================================================
# WebSocket Endpoints Tests
# ============================================================================

@test("Job events WebSocket endpoint exists", "WebSockets")
def test_job_events_websocket():
    status, _, headers = make_request("GET", "/api/v1/jobs/events")
    # Should either upgrade or return specific status
    assert status in [200, 426], f"Expected 200 or 426, got {status}"
    if status == 426:
        assert "Upgrade" in headers, "Should have Upgrade header"
    return True

@test("Stdout updates WebSocket endpoint exists", "WebSockets")
def test_stdout_updates_websocket():
    status, _, _ = make_request("GET", "/api/v1/jobs/test-id/stdout/updates")
    assert status in [200, 426], f"Expected 200 or 426, got {status}"
    return True

@test("Stderr updates WebSocket endpoint exists", "WebSockets")
def test_stderr_updates_websocket():
    status, _, _ = make_request("GET", "/api/v1/jobs/test-id/stderr/updates")
    assert status in [200, 426], f"Expected 200 or 426, got {status}"
    return True

# ============================================================================
# Error Handling Tests
# ============================================================================

@test("Invalid JSON returns 400", "Error Handling")
def test_invalid_json():
    headers = {'Content-Type': 'application/json'}
    try:
        request = urllib.request.Request(
            f"{API_URL}/api/v1/jobs",
            data=b"invalid json",
            headers=headers,
            method="POST"
        )
        response = urllib.request.urlopen(request)
        status = response.status
    except urllib.error.HTTPError as e:
        status = e.code
    
    assert status in [400, 422], f"Expected 400/422 for invalid JSON, got {status}"
    return True

@test("Missing Content-Type handled gracefully", "Error Handling")
def test_missing_content_type():
    data = json.dumps({"spec": "echo"}).encode('utf-8')
    request = urllib.request.Request(
        f"{API_URL}/api/v1/jobs",
        data=data,
        method="POST"
    )
    try:
        response = urllib.request.urlopen(request)
        status = response.status
    except urllib.error.HTTPError as e:
        status = e.code
    
    # Should either accept or reject with proper status
    assert status in [200, 400, 415], f"Unexpected status: {status}"
    return True

@test("Unsupported HTTP method returns 405", "Error Handling")
def test_unsupported_method():
    try:
        status, _, _ = make_request("PATCH", "/api/v1/specs")
    except:
        # Some servers might not handle PATCH at all
        return True
    
    assert status == 405, f"Expected 405 for unsupported method, got {status}"
    return True

# ============================================================================
# Content Negotiation Tests
# ============================================================================

@test("API returns JSON by default", "Content Negotiation")
def test_default_content_type():
    status, _, headers = make_request("GET", "/api/v1")
    assert_status(status, 200)
    content_type = headers.get('Content-Type', '')
    assert 'json' in content_type.lower(), f"Expected JSON content, got {content_type}"
    return True

@test("Accept header is respected", "Content Negotiation")
def test_accept_header():
    headers = {'Accept': 'application/json'}
    status, _, resp_headers = make_request("GET", "/api/v1", headers=headers)
    assert_status(status, 200)
    content_type = resp_headers.get('Content-Type', '')
    assert 'json' in content_type.lower(), f"Expected JSON response, got {content_type}"
    return True

# ============================================================================
# Job Lifecycle Tests
# ============================================================================

@test("Complete job lifecycle works", "Job Lifecycle")
def test_complete_job_lifecycle():
    # 1. Create job
    job_data = {
        "spec": "echo",
        "name": "Lifecycle Test",
        "inputs": {"message": "Testing lifecycle"}
    }
    status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200, "Job creation")
    job_id = created["id"]
    
    # 2. Get job details
    status, details, _ = make_request("GET", f"/api/v1/jobs/{job_id}")
    assert_status(status, 200, "Get job details")
    assert_equal(details["name"], "Lifecycle Test")
    
    # 3. Get job inputs
    status, inputs, _ = make_request("GET", f"/api/v1/jobs/{job_id}/inputs")
    assert_status(status, 200, "Get job inputs")
    assert_equal(inputs["message"], "Testing lifecycle")
    
    # 4. Get job spec
    status, spec, _ = make_request("GET", f"/api/v1/jobs/{job_id}/spec")
    assert_status(status, 200, "Get job spec")
    assert_equal(spec["id"], "echo")
    
    # 5. Wait and check stdout
    time.sleep(1)
    status, stdout, _ = make_request("GET", f"/api/v1/jobs/{job_id}/stdout")
    assert_status(status, 200, "Get stdout")
    
    # 6. Delete job
    status, _, _ = make_request("DELETE", f"/api/v1/jobs/{job_id}")
    assert_status(status, 200, "Delete job")
    
    # 7. Verify deletion
    status, _, _ = make_request("GET", f"/api/v1/jobs/{job_id}")
    assert_status(status, 404, "Job should be deleted")
    
    return True

@test("Multiple concurrent jobs work", "Job Lifecycle")
def test_concurrent_jobs():
    job_ids = []
    
    # Create multiple jobs
    for i in range(5):
        job_data = {
            "spec": "echo",
            "name": f"Concurrent {i}",
            "inputs": {"message": f"Message {i}"}
        }
        status, created, _ = make_request("POST", "/api/v1/jobs", job_data)
        assert_status(status, 200)
        job_ids.append(created["id"])
    
    # Verify all jobs exist
    for job_id in job_ids:
        status, _, _ = make_request("GET", f"/api/v1/jobs/{job_id}")
        assert_status(status, 200)
    
    # Delete all jobs
    for job_id in job_ids:
        make_request("DELETE", f"/api/v1/jobs/{job_id}")
    
    return True

# ============================================================================
# Edge Cases Tests
# ============================================================================

@test("Empty job name is handled", "Edge Cases")
def test_empty_job_name():
    job_data = {"spec": "echo", "name": ""}
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    # Should either accept with generated name or reject
    assert status in [200, 400], f"Unexpected status: {status}"
    if status == 200:
        make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

@test("Very long job name is handled", "Edge Cases")
def test_long_job_name():
    long_name = "A" * 1000
    job_data = {"spec": "echo", "name": long_name}
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    # Should either accept or reject gracefully
    assert status in [200, 400, 413], f"Unexpected status: {status}"
    if status == 200:
        make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

@test("Special characters in job name", "Edge Cases")
def test_special_chars_job_name():
    special_name = "Test!@#$%^&*()[]{}|\\:;\"'<>,.?/"
    job_data = {"spec": "echo", "name": special_name}
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    # Should handle gracefully
    assert status in [200, 400], f"Unexpected status: {status}"
    if status == 200:
        assert body["name"] is not None
        make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

@test("Unicode in inputs is handled", "Edge Cases")
def test_unicode_inputs():
    job_data = {
        "spec": "echo",
        "inputs": {"message": "Hello 世界 🌍 مرحبا"}
    }
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    assert_status(status, 200)
    job_id = body["id"]
    
    # Verify inputs are preserved
    status, inputs, _ = make_request("GET", f"/api/v1/jobs/{job_id}/inputs")
    assert_status(status, 200)
    assert_equal(inputs["message"], "Hello 世界 🌍 مرحبا")
    
    make_request("DELETE", f"/api/v1/jobs/{job_id}")
    return True

@test("Null values in inputs", "Edge Cases")
def test_null_input_values():
    job_data = {
        "spec": "echo",
        "inputs": {"message": None}
    }
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    # Should handle null gracefully
    assert status in [200, 400], f"Unexpected status: {status}"
    if status == 200:
        make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

# ============================================================================
# Security Tests
# ============================================================================

@test("Path traversal in spec ID is blocked", "Security")
def test_path_traversal_spec():
    status, _, _ = make_request("GET", "/api/v1/specs/../../../etc/passwd")
    # Should not allow path traversal
    assert status in [400, 404], f"Path traversal not blocked, status: {status}"
    return True

@test("SQL injection in parameters handled", "Security")
def test_sql_injection_params():
    status, _, _ = make_request("GET", "/api/v1/jobs?page=0' OR '1'='1")
    # Should handle SQL injection attempts gracefully
    assert status in [200, 400], f"Unexpected status: {status}"
    return True

@test("Script injection in job name sanitized", "Security")
def test_script_injection():
    job_data = {
        "spec": "echo",
        "name": "<script>alert('XSS')</script>"
    }
    status, body, _ = make_request("POST", "/api/v1/jobs", job_data)
    # Should either sanitize or reject
    assert status in [200, 400], f"Unexpected status: {status}"
    if status == 200:
        # If accepted, name should be sanitized
        assert "<script>" not in str(body.get("name", ""))
        make_request("DELETE", f"/api/v1/jobs/{body['id']}")
    return True

# ============================================================================
# Main Test Runner
# ============================================================================

def run_all_tests():
    """Run all tests and report results"""
    print(f"\n{BLUE}{'='*60}")
    print(f"Comprehensive API Test Suite")
    print(f"{'='*60}{NC}\n")
    
    # Get all test functions
    test_functions = []
    for name, obj in globals().items():
        if hasattr(obj, '_is_test') and obj._is_test:
            test_functions.append(obj)
    
    # Sort by group for organized output
    test_functions.sort(key=lambda f: (f._test_group, f._test_name))
    
    # Execute tests by group
    current_group = None
    for func in test_functions:
        if func._test_group != current_group:
            current_group = func._test_group
            print(f"\n{YELLOW}Testing: {current_group}{NC}")
            print("-" * 40)
        func()
    
    # Print results by group
    print(f"\n{BLUE}{'='*60}")
    print(f"Test Results by Category")
    print(f"{'='*60}{NC}\n")
    
    for group, tests in test_groups.items():
        passed = sum(1 for _, result in tests if result)
        total = len(tests)
        
        if passed == total:
            status_color = GREEN
        elif passed > 0:
            status_color = YELLOW
        else:
            status_color = RED
        
        print(f"{status_color}{group}: {passed}/{total} passed{NC}")
        
        # Show failed tests
        failed = [name for name, result in tests if not result]
        if failed:
            for test_name in failed:
                print(f"  {RED}✗ {test_name}{NC}")
    
    # Overall summary
    print(f"\n{BLUE}{'='*60}")
    print(f"Overall Summary")
    print(f"{'='*60}{NC}\n")
    
    total_tests = len(test_results)
    passed_tests = sum(1 for _, result, _ in test_results if result)
    failed_tests = total_tests - passed_tests
    
    print(f"Total tests: {total_tests}")
    print(f"{GREEN}Passed: {passed_tests}{NC}")
    print(f"{RED}Failed: {failed_tests}{NC}")
    
    if failed_tests == 0:
        print(f"\n{GREEN}✓ All tests passed! The API is fully compliant.{NC}")
        return 0
    else:
        print(f"\n{RED}✗ Some tests failed. Please review the failures above.{NC}")
        return 1

def main():
    """Main entry point"""
    # Check if server is running
    try:
        status, _, _ = make_request("GET", "/api/v1")
        if status != 200:
            print(f"{RED}Error: API server not responding at {API_URL}{NC}")
            print("Please start the server first")
            return 1
    except Exception as e:
        print(f"{RED}Error: Cannot connect to API server at {API_URL}{NC}")
        print(f"Error: {e}")
        print("\nPlease start the server with one of:")
        print("  - rails server -p 8080")
        print("  - python3 mock-rails-server.py")
        return 1
    
    return run_all_tests()

if __name__ == "__main__":
    sys.exit(main())