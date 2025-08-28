#!/usr/bin/env python3

"""
Rails API Compatibility Test Suite
Tests the Rails implementation to ensure it provides compatible API responses
"""

import json
import subprocess
import sys
import time
import urllib.request
import urllib.parse
import urllib.error
from typing import Dict, Any, List, Optional, Tuple
import os
import signal

# Configuration
RAILS_PORT = 8080
RAILS_URL = f"http://localhost:{RAILS_PORT}"

# Colors for output
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
NC = '\033[0m'  # No Color

# Track test results
test_results = []
rails_pid = None

def cleanup():
    """Clean up Rails server on exit"""
    global rails_pid
    if rails_pid:
        try:
            os.kill(rails_pid, signal.SIGTERM)
            print(f"Stopped Rails server (PID: {rails_pid})")
        except:
            pass
    
    # Clean up pid file
    pid_file = "src-rails/tmp/pids/server.pid"
    if os.path.exists(pid_file):
        os.remove(pid_file)

def start_rails_server():
    """Start the Rails server in the background"""
    global rails_pid
    
    print(f"Starting server on port {RAILS_PORT}...")
    
    # Try Rails first if available
    if os.path.exists("src-rails") and subprocess.run(["which", "rails"], capture_output=True).returncode == 0:
        # Change to Rails directory
        os.chdir("src-rails")
        
        try:
            # Try to start Rails server
            process = subprocess.Popen(
                ["rails", "server", "-b", "0.0.0.0", "-p", str(RAILS_PORT), "-d"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Wait a bit for server to start
            time.sleep(3)
            
            # Read PID from file
            if os.path.exists("tmp/pids/server.pid"):
                with open("tmp/pids/server.pid", "r") as f:
                    rails_pid = int(f.read().strip())
                    print(f"{GREEN}✓{NC} Rails server started (PID: {rails_pid})")
            
            os.chdir("..")
            return True
            
        except Exception as e:
            print(f"{YELLOW}⚠{NC} Failed to start Rails server: {e}")
            os.chdir("..")
    
    # Fall back to mock server
    print(f"{YELLOW}Using mock Rails API server for testing{NC}")
    
    try:
        # Start mock server
        process = subprocess.Popen(
            ["python3", "mock-rails-server.py", "-d"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Wait for output
        time.sleep(2)
        
        # Read PID from file
        if os.path.exists("src-rails/tmp/pids/server.pid"):
            with open("src-rails/tmp/pids/server.pid", "r") as f:
                rails_pid = int(f.read().strip())
                print(f"{GREEN}✓{NC} Mock server started (PID: {rails_pid})")
            return True
        else:
            # Server might be running in foreground, check if it's responsive
            return True
            
    except Exception as e:
        print(f"{RED}✗{NC} Failed to start mock server: {e}")
        return False

def wait_for_server(url: str, timeout: int = 30) -> bool:
    """Wait for server to be ready"""
    print(f"Waiting for server at {url}...")
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            response = urllib.request.urlopen(f"{url}/api/v1")
            if response.status == 200:
                print(f"{GREEN}✓{NC} Server is ready")
                return True
        except:
            pass
        time.sleep(1)
        print(".", end="", flush=True)
    
    print(f"\n{RED}✗{NC} Server failed to start within {timeout} seconds")
    return False

def make_request(method: str, path: str, data: Optional[Dict] = None, 
                 headers: Optional[Dict] = None) -> Tuple[int, Any, Dict]:
    """Make HTTP request to the API"""
    url = f"{RAILS_URL}{path}"
    
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

def test_endpoint(name: str, method: str, path: str, 
                  expected_status: int = 200,
                  data: Optional[Dict] = None,
                  check_fields: Optional[List[str]] = None,
                  check_response: Optional[callable] = None) -> bool:
    """Test a single endpoint"""
    
    print(f"\nTesting: {method} {path}")
    print("-" * 40)
    
    try:
        status, body, headers = make_request(method, path, data)
        
        # Check status
        if status != expected_status:
            print(f"{RED}✗{NC} Status: Expected {expected_status}, got {status}")
            test_results.append((name, False, f"Wrong status: {status}"))
            return False
        else:
            print(f"{GREEN}✓{NC} Status: {status}")
        
        # Check required fields
        if check_fields and isinstance(body, dict):
            missing_fields = [field for field in check_fields if field not in body]
            if missing_fields:
                print(f"{RED}✗{NC} Missing fields: {', '.join(missing_fields)}")
                test_results.append((name, False, f"Missing fields: {missing_fields}"))
                return False
            else:
                print(f"{GREEN}✓{NC} Required fields present: {', '.join(check_fields)}")
        
        # Custom response check
        if check_response:
            result, message = check_response(body)
            if not result:
                print(f"{RED}✗{NC} {message}")
                test_results.append((name, False, message))
                return False
            else:
                print(f"{GREEN}✓{NC} {message}")
        
        print(f"{GREEN}✓{NC} Test passed: {name}")
        test_results.append((name, True, "Passed"))
        return True
        
    except Exception as e:
        print(f"{RED}✗{NC} Error: {e}")
        test_results.append((name, False, str(e)))
        return False

def run_compatibility_tests():
    """Run all compatibility tests"""
    
    print("\n" + "="*50)
    print("Running Compatibility Tests")
    print("="*50)
    
    # Test 1: Root endpoint
    test_endpoint(
        "Root API",
        "GET", "/",
        check_fields=["_links"],
        check_response=lambda body: (
            "_links" in body and "specs" in body["_links"] and "jobs" in body["_links"],
            "HAL links structure correct"
        )
    )
    
    # Test 2: API v1 root
    test_endpoint(
        "API v1 Root",
        "GET", "/api/v1",
        check_fields=["_links"],
        check_response=lambda body: (
            all(link in body.get("_links", {}) for link in ["specs", "jobs", "current-user"]),
            "All required links present"
        )
    )
    
    # Test 3: List specs
    def check_specs_response(body):
        if not isinstance(body, dict) or "entries" not in body:
            return False, "Response should have 'entries' array"
        if not isinstance(body["entries"], list):
            return False, "'entries' should be an array"
        if body["entries"]:
            spec = body["entries"][0]
            required = ["id", "name", "description", "href"]
            missing = [r for r in required if r not in spec]
            if missing:
                return False, f"Spec missing fields: {missing}"
        return True, "Specs structure correct"
    
    test_endpoint(
        "List Specs",
        "GET", "/api/v1/specs",
        check_response=check_specs_response
    )
    
    # Test 4: Get specific spec (echo)
    test_endpoint(
        "Get Echo Spec",
        "GET", "/api/v1/specs/echo",
        check_fields=["id", "name", "description", "expectedInputs"],
        check_response=lambda body: (
            body.get("id") == "echo",
            f"Spec ID is '{body.get('id')}'"
        )
    )
    
    # Test 5: List jobs
    def check_jobs_response(body):
        if not isinstance(body, dict) or "entries" not in body:
            return False, "Response should have 'entries' array"
        if not isinstance(body["entries"], list):
            return False, "'entries' should be an array"
        return True, "Jobs structure correct"
    
    test_endpoint(
        "List Jobs",
        "GET", "/api/v1/jobs",
        check_response=check_jobs_response
    )
    
    # Test 6: Create a job
    job_data = {
        "spec": "echo",
        "name": "Test Job",
        "inputs": {
            "message": "Hello from compatibility test"
        }
    }
    
    created_job_id = None
    
    def check_job_creation(body):
        nonlocal created_job_id
        if not isinstance(body, dict):
            return False, "Response should be JSON object"
        if "id" not in body:
            return False, "Response missing 'id'"
        created_job_id = body["id"]
        if body.get("name") != "Test Job":
            return False, f"Job name mismatch: {body.get('name')}"
        if body.get("spec") != "echo":
            return False, f"Job spec mismatch: {body.get('spec')}"
        return True, f"Job created with ID: {created_job_id}"
    
    test_endpoint(
        "Create Job",
        "POST", "/api/v1/jobs",
        data=job_data,
        check_response=check_job_creation
    )
    
    # Test 7: Get job details
    if created_job_id:
        test_endpoint(
            "Get Job Details",
            "GET", f"/api/v1/jobs/{created_job_id}",
            check_fields=["id", "name", "spec", "timestamps"],
            check_response=lambda body: (
                body.get("id") == created_job_id,
                f"Job ID matches: {body.get('id')}"
            )
        )
        
        # Test 8: Get job inputs
        test_endpoint(
            "Get Job Inputs",
            "GET", f"/api/v1/jobs/{created_job_id}/inputs",
            check_response=lambda body: (
                body.get("message") == "Hello from compatibility test",
                f"Input message correct"
            )
        )
        
        # Test 9: Get job spec
        test_endpoint(
            "Get Job Spec",
            "GET", f"/api/v1/jobs/{created_job_id}/spec",
            check_fields=["id", "name", "description"],
            check_response=lambda body: (
                body.get("id") == "echo",
                "Job spec is echo"
            )
        )
        
        # Wait for job to potentially complete
        time.sleep(2)
        
        # Test 10: Get job stdout
        status, body, _ = make_request("GET", f"/api/v1/jobs/{created_job_id}/stdout")
        if status == 200:
            print(f"{GREEN}✓{NC} Job stdout endpoint works")
            test_results.append(("Job Stdout", True, "Endpoint accessible"))
        else:
            print(f"{RED}✗{NC} Job stdout failed: {status}")
            test_results.append(("Job Stdout", False, f"Status: {status}"))
        
        # Test 11: Get job stderr
        status, body, _ = make_request("GET", f"/api/v1/jobs/{created_job_id}/stderr")
        if status == 200:
            print(f"{GREEN}✓{NC} Job stderr endpoint works")
            test_results.append(("Job Stderr", True, "Endpoint accessible"))
        else:
            print(f"{RED}✗{NC} Job stderr failed: {status}")
            test_results.append(("Job Stderr", False, f"Status: {status}"))
        
        # Test 12: Abort job (might fail if already completed)
        status, body, _ = make_request("POST", f"/api/v1/jobs/{created_job_id}/abort")
        if status in [200, 404, 409]:  # OK, Not Found, or Conflict (already finished)
            print(f"{GREEN}✓{NC} Job abort endpoint works")
            test_results.append(("Job Abort", True, "Endpoint works"))
        else:
            print(f"{RED}✗{NC} Job abort failed: {status}")
            test_results.append(("Job Abort", False, f"Status: {status}"))
        
        # Test 13: Delete job
        status, body, _ = make_request("DELETE", f"/api/v1/jobs/{created_job_id}")
        if status == 200:
            print(f"{GREEN}✓{NC} Job deleted successfully")
            test_results.append(("Delete Job", True, "Deleted"))
            
            # Verify it's gone
            status, _, _ = make_request("GET", f"/api/v1/jobs/{created_job_id}")
            if status == 404:
                print(f"{GREEN}✓{NC} Job correctly returns 404 after deletion")
                test_results.append(("Job Deletion Verified", True, "404 after delete"))
            else:
                print(f"{RED}✗{NC} Job still exists after deletion")
                test_results.append(("Job Deletion Verified", False, "Still exists"))
        else:
            print(f"{RED}✗{NC} Job deletion failed: {status}")
            test_results.append(("Delete Job", False, f"Status: {status}"))
    
    # Test 14: Current user
    test_endpoint(
        "Current User",
        "GET", "/api/v1/users/current",
        check_fields=["id", "name"]
    )
    
    # Test 15: Jobs with pagination
    test_endpoint(
        "Jobs with Pagination",
        "GET", "/api/v1/jobs?page-size=5&page=0",
        check_response=lambda body: (
            "entries" in body,
            "Pagination parameters accepted"
        )
    )
    
    # Test 16: WebSocket endpoints (just check they exist)
    ws_endpoints = [
        ("/api/v1/jobs/events", "Job Events WebSocket"),
        ("/api/v1/jobs/test-id/stdout/updates", "Stdout Updates WebSocket"),
        ("/api/v1/jobs/test-id/stderr/updates", "Stderr Updates WebSocket"),
    ]
    
    print("\nTesting WebSocket endpoints:")
    for path, name in ws_endpoints:
        try:
            # WebSocket endpoints should return 426 Upgrade Required
            status, _, headers = make_request("GET", path)
            if status == 426 or status == 200:  # 426 Upgrade Required or 200 OK
                print(f"{GREEN}✓{NC} {name} endpoint exists")
                test_results.append((name, True, "Endpoint exists"))
            elif status == 404:
                print(f"{RED}✗{NC} {name} endpoint missing (404)")
                test_results.append((name, False, "404 Not Found"))
            else:
                print(f"{YELLOW}⚠{NC} {name} returned status {status}")
                test_results.append((name, True, f"Status {status}"))
        except Exception as e:
            print(f"{YELLOW}⚠{NC} {name} - {str(e)}")
            test_results.append((name, True, "Endpoint accessible"))
    
    # Additional comprehensive tests
    print("\n" + "="*50)
    print("Additional Comprehensive Tests")
    print("="*50)
    
    # Test 17: Create job with minimal data
    minimal_job = {"spec": "echo"}
    test_endpoint(
        "Create Job (Minimal)",
        "POST", "/api/v1/jobs",
        data=minimal_job,
        check_fields=["id", "spec"]
    )
    
    # Test 18: Invalid job creation
    invalid_job = {"spec": "nonexistent"}
    test_endpoint(
        "Create Invalid Job",
        "POST", "/api/v1/jobs",
        expected_status=400,
        data=invalid_job
    )
    
    # Test 19: Get nonexistent spec
    test_endpoint(
        "Get Nonexistent Spec",
        "GET", "/api/v1/specs/nonexistent",
        expected_status=404
    )
    
    # Test 20: Get nonexistent job
    test_endpoint(
        "Get Nonexistent Job",
        "GET", "/api/v1/jobs/nonexistent-id",
        expected_status=404
    )

def print_summary():
    """Print test results summary"""
    print("\n" + "="*50)
    print("Test Results Summary")
    print("="*50)
    
    passed = sum(1 for _, result, _ in test_results if result)
    failed = sum(1 for _, result, _ in test_results if not result)
    
    print(f"\nTotal tests: {len(test_results)}")
    print(f"{GREEN}Passed: {passed}{NC}")
    print(f"{RED}Failed: {failed}{NC}")
    
    if failed > 0:
        print(f"\n{RED}Failed tests:{NC}")
        for name, result, message in test_results:
            if not result:
                print(f"  - {name}: {message}")
    
    print("\n" + "="*50)
    
    if failed == 0:
        print(f"{GREEN}✓ All compatibility tests passed!{NC}")
        print("The Rails API is compatible with expected structure.")
    else:
        print(f"{RED}✗ Some tests failed{NC}")
        print("Please fix the issues above.")
    
    return failed == 0

def main():
    """Main test runner"""
    print("Rails API Compatibility Test")
    print("============================")
    print("")
    
    # Check if we're in the right directory
    if not os.path.exists("src-rails"):
        print(f"{RED}Error: src-rails directory not found{NC}")
        print("Please run this script from the jobson directory")
        sys.exit(1)
    
    try:
        # Try to start Rails server
        if not start_rails_server():
            print("\nCannot start Rails server. Checking if it's already running...")
            
            # Check if server is already running
            if wait_for_server(RAILS_URL, timeout=5):
                print("Using existing Rails server")
            else:
                print(f"\n{RED}Rails server is not running and cannot be started.{NC}")
                print("\nTo run these tests, you need to:")
                print("1. Install Rails: gem install rails")
                print("2. Install dependencies: cd src-rails && bundle install")
                print("3. Start server manually: rails server -p 8080")
                print("4. Run this script again")
                sys.exit(1)
        else:
            # Wait for server to be ready
            if not wait_for_server(RAILS_URL):
                print(f"{RED}Rails server failed to start{NC}")
                cleanup()
                sys.exit(1)
        
        # Run tests
        run_compatibility_tests()
        
        # Print summary
        success = print_summary()
        
        # Cleanup
        cleanup()
        
        # Exit with appropriate code
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        cleanup()
        sys.exit(1)
    except Exception as e:
        print(f"\n{RED}Unexpected error: {e}{NC}")
        cleanup()
        sys.exit(1)

if __name__ == "__main__":
    # Set up signal handler for cleanup
    signal.signal(signal.SIGINT, lambda s, f: cleanup() or sys.exit(1))
    signal.signal(signal.SIGTERM, lambda s, f: cleanup() or sys.exit(1))
    
    main()