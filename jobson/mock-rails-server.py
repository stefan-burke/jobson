#!/usr/bin/env python3

"""
Mock Rails API Server for Testing
Simulates the Rails API endpoints for compatibility testing
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import uuid
from datetime import datetime
import threading
import time
from urllib.parse import urlparse, parse_qs
import os
import sys

# Port configuration
PORT = 8080

# In-memory storage
jobs = {}
job_outputs = {}

class MockRailsHandler(BaseHTTPRequestHandler):
    """Mock Rails API request handler"""
    
    def _send_json_response(self, data, status=200):
        """Send JSON response"""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))
    
    def _send_text_response(self, text, status=200):
        """Send text response"""
        self.send_response(status)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(text.encode('utf-8'))
    
    def _get_post_data(self):
        """Get POST data as dict"""
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length:
            post_data = self.rfile.read(content_length)
            return json.loads(post_data.decode('utf-8'))
        return {}
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        query_params = parse_qs(parsed_path.query)
        
        # Root endpoint
        if path == '/':
            self._send_json_response({
                "_links": {
                    "specs": {"href": "/api/v1/specs"},
                    "jobs": {"href": "/api/v1/jobs"}
                }
            })
        
        # API v1 root
        elif path == '/api/v1':
            self._send_json_response({
                "_links": {
                    "specs": {"href": "/api/v1/specs"},
                    "jobs": {"href": "/api/v1/jobs"},
                    "current-user": {"href": "/api/v1/users/current"}
                }
            })
        
        # List specs
        elif path == '/api/v1/specs':
            self._send_json_response({
                "entries": [
                    {
                        "id": "echo",
                        "name": "Echo",
                        "description": "Simple echo command that prints input to stdout",
                        "href": "/api/v1/specs/echo"
                    },
                    {
                        "id": "sleep",
                        "name": "Sleep",
                        "description": "Sleep for specified seconds",
                        "href": "/api/v1/specs/sleep"
                    }
                ]
            })
        
        # Get specific spec
        elif path == '/api/v1/specs/echo':
            self._send_json_response({
                "id": "echo",
                "name": "Echo",
                "description": "Simple echo command that prints input to stdout",
                "expectedInputs": [
                    {
                        "id": "message",
                        "type": "string",
                        "name": "Message",
                        "description": "The message to echo",
                        "default": "Hello, World!"
                    }
                ],
                "expectedOutputs": [],
                "execution": {
                    "application": "echo",
                    "arguments": ["${inputs.message}"]
                }
            })
        
        elif path == '/api/v1/specs/sleep':
            self._send_json_response({
                "id": "sleep",
                "name": "Sleep",
                "description": "Sleep for specified seconds",
                "expectedInputs": [
                    {
                        "id": "seconds",
                        "type": "integer",
                        "name": "Seconds",
                        "description": "Number of seconds to sleep",
                        "default": 1
                    }
                ],
                "expectedOutputs": [],
                "execution": {
                    "application": "sleep",
                    "arguments": ["${inputs.seconds}"]
                }
            })
        
        # List jobs
        elif path == '/api/v1/jobs':
            page_size = int(query_params.get('page-size', [100])[0])
            page = int(query_params.get('page', [0])[0])
            
            job_list = list(jobs.values())
            start = page * page_size
            end = start + page_size
            
            self._send_json_response({
                "entries": job_list[start:end],
                "page": page,
                "pageSize": page_size,
                "total": len(jobs)
            })
        
        # WebSocket endpoints (special handling)
        elif path == '/api/v1/jobs/events':
            self.send_response(426)  # Upgrade Required
            self.send_header('Upgrade', 'websocket')
            self.end_headers()
        
        elif '/stdout/updates' in path or '/stderr/updates' in path:
            self.send_response(426)  # Upgrade Required
            self.send_header('Upgrade', 'websocket')
            self.end_headers()
        
        # Get job details
        elif path.startswith('/api/v1/jobs/'):
            parts = path.split('/')
            if len(parts) == 5:  # /api/v1/jobs/{id}
                job_id = parts[4]
                if job_id in jobs:
                    self._send_json_response(jobs[job_id])
                else:
                    self._send_json_response({"error": "Job not found"}, 404)
            
            elif len(parts) == 6:  # /api/v1/jobs/{id}/{endpoint}
                job_id = parts[4]
                endpoint = parts[5]
                
                if job_id not in jobs and job_id != "test-id":
                    self._send_json_response({"error": "Job not found"}, 404)
                    return
                
                if endpoint == 'stdout':
                    output = job_outputs.get(job_id, {}).get('stdout', '')
                    self._send_text_response(output)
                
                elif endpoint == 'stderr':
                    output = job_outputs.get(job_id, {}).get('stderr', '')
                    self._send_text_response(output)
                
                elif endpoint == 'inputs':
                    if job_id in jobs:
                        self._send_json_response(jobs[job_id].get('inputs', {}))
                    else:
                        self._send_json_response({})
                
                elif endpoint == 'spec':
                    if job_id in jobs:
                        spec_id = jobs[job_id].get('spec', 'echo')
                        # Return the spec details
                        if spec_id == 'echo':
                            self._send_json_response({
                                "id": "echo",
                                "name": "Echo",
                                "description": "Simple echo command that prints input to stdout",
                                "expectedInputs": [
                                    {
                                        "id": "message",
                                        "type": "string",
                                        "name": "Message",
                                        "description": "The message to echo"
                                    }
                                ]
                            })
                        else:
                            self._send_json_response({
                                "id": spec_id,
                                "name": spec_id.capitalize(),
                                "description": f"Spec for {spec_id}"
                            })
                    else:
                        self._send_json_response({"error": "Job not found"}, 404)
                
                elif endpoint in ['events', 'stdout', 'stderr']:
                    if endpoint == 'events' or path.endswith('/updates'):
                        # WebSocket endpoints - return upgrade required
                        self.send_response(426)  # Upgrade Required
                        self.send_header('Upgrade', 'websocket')
                        self.end_headers()
                    else:
                        # Regular stdout/stderr already handled above
                        self._send_json_response({"error": "Not found"}, 404)
                
                else:
                    self._send_json_response({"error": "Unknown endpoint"}, 404)
        
        # Current user
        elif path == '/api/v1/users/current':
            self._send_json_response({
                "id": "guest",
                "name": "Guest User"
            })
        
        # Unknown spec
        elif path.startswith('/api/v1/specs/'):
            self._send_json_response({"error": "Spec not found"}, 404)
        
        else:
            self._send_json_response({"error": "Not found"}, 404)
    
    def do_POST(self):
        """Handle POST requests"""
        path = self.path
        
        # Create job
        if path == '/api/v1/jobs':
            data = self._get_post_data()
            
            # Validate spec exists
            spec_id = data.get('spec')
            if spec_id not in ['echo', 'sleep']:
                self._send_json_response({"error": "Invalid spec"}, 400)
                return
            
            # Create job
            job_id = str(uuid.uuid4())
            job = {
                "id": job_id,
                "name": data.get('name', f"Job {job_id[:8]}"),
                "spec": spec_id,
                "inputs": data.get('inputs', {}),
                "timestamps": {
                    "submitted": datetime.now().isoformat(),
                    "started": datetime.now().isoformat(),
                    "finished": None
                },
                "latestStatus": "SUBMITTED"
            }
            
            jobs[job_id] = job
            
            # Simulate job execution
            if spec_id == 'echo':
                message = data.get('inputs', {}).get('message', 'Hello, World!')
                job_outputs[job_id] = {
                    'stdout': message + '\n',
                    'stderr': ''
                }
                job['latestStatus'] = 'FINISHED'
                job['timestamps']['finished'] = datetime.now().isoformat()
            
            self._send_json_response(job)
        
        # Abort job
        elif path.startswith('/api/v1/jobs/') and path.endswith('/abort'):
            job_id = path.split('/')[4]
            if job_id in jobs:
                jobs[job_id]['latestStatus'] = 'ABORTED'
                self._send_json_response({"message": "Job aborted"})
            else:
                self._send_json_response({"error": "Job not found"}, 404)
        
        else:
            self._send_json_response({"error": "Not found"}, 404)
    
    def do_DELETE(self):
        """Handle DELETE requests"""
        path = self.path
        
        # Delete job
        if path.startswith('/api/v1/jobs/'):
            job_id = path.split('/')[4]
            if job_id in jobs:
                del jobs[job_id]
                if job_id in job_outputs:
                    del job_outputs[job_id]
                self._send_json_response({"message": "Job deleted"})
            else:
                self._send_json_response({"error": "Job not found"}, 404)
        else:
            self._send_json_response({"error": "Not found"}, 404)
    
    def log_message(self, format, *args):
        """Suppress log messages"""
        pass

def run_server():
    """Run the mock server"""
    server = HTTPServer(('', PORT), MockRailsHandler)
    print(f"Mock Rails API server running on port {PORT}")
    print("Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()

if __name__ == "__main__":
    # Check if running as daemon
    if len(sys.argv) > 1 and sys.argv[1] == '-d':
        # Fork and run in background
        pid = os.fork()
        if pid > 0:
            # Parent process
            print(f"Mock server started in background (PID: {pid})")
            # Create pid file for compatibility
            os.makedirs("src-rails/tmp/pids", exist_ok=True)
            with open("src-rails/tmp/pids/server.pid", "w") as f:
                f.write(str(pid))
            sys.exit(0)
        else:
            # Child process - run server
            run_server()
    else:
        run_server()