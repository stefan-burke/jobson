#!/usr/bin/env nix-shell
#!nix-shell -i bash -p maven curl libyaml

# Run Java API server on port 8080

set -e
set -x  # Enable verbose command execution

echo "Java API Server"
echo "==============="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Function to cleanup
cleanup() {
    echo "Cleaning up..."
    if [ ! -z "$JAVA_PID" ]; then
        kill $JAVA_PID 2>/dev/null || true
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Build Java backend if needed
if [ ! -f target/jobson*.jar ]; then
    echo "Building Java backend..."
    mvn clean package -DskipTests
fi

# Create required directories
mkdir -p /tmp/jobson-jobs
mkdir -p /tmp/jobson-wds

# Use existing specs or create specs directory
if [ -d "src-rails/workspace/specs" ]; then
    echo "Using Rails specs..."
    mkdir -p specs
    cp -r src-rails/workspace/specs/* specs/
elif [ ! -d "specs" ]; then
    echo "Creating empty specs directory..."
    mkdir -p specs
fi

# Create empty users file
touch /tmp/jobson-users

# Create configuration file
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

echo "Starting Java server on port 8080..."

# Start Java server
mvn exec:java -Dexec.mainClass="com.github.jobson.App" -Dexec.args="serve test-config.yml" &
JAVA_PID=$!

# Wait for server to be ready
echo "Waiting for server to start..."
for i in {1..20}; do
    if curl -s http://localhost:8080/api/v1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Java server is ready on http://localhost:8080"
        echo ""
        echo "Server is running. Press Ctrl+C to stop."
        break
    fi
    sleep 1
done

# Keep the script running
wait $JAVA_PID