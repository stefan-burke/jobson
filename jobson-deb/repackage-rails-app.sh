#!/bin/bash

VERSION=$1

# Prepare the directory structure
rm -rf "target/jobson-deb-${VERSION}"
mkdir -p "target/jobson-deb-${VERSION}/usr/share/jobson"
mkdir -p "target/jobson-deb-${VERSION}/usr/bin"

# Copy the Rails app
cp -r ../jobson/src-rails/* "target/jobson-deb-${VERSION}/usr/share/jobson/"

# Remove development-only files
rm -rf "target/jobson-deb-${VERSION}/usr/share/jobson/tmp"
rm -rf "target/jobson-deb-${VERSION}/usr/share/jobson/log"
rm -rf "target/jobson-deb-${VERSION}/usr/share/jobson/storage"
rm -rf "target/jobson-deb-${VERSION}/usr/share/jobson/workspace"
rm -f "target/jobson-deb-${VERSION}/usr/share/jobson/.byebug_history"

# Create the jobson command wrapper
cat <<'EOF' > "target/jobson-deb-${VERSION}/usr/bin/jobson"
#!/bin/bash

JOBSON_DIR="/usr/share/jobson"

# Ensure bundler is installed
if ! command -v bundle &> /dev/null; then
    echo "Error: bundler is not installed. Please install it with: gem install bundler"
    exit 1
fi

# Handle different commands
case "$1" in
    new)
        # Create a new workspace
        if [ -z "$2" ]; then
            echo "Usage: jobson new <workspace_dir>"
            exit 1
        fi
        
        WORKSPACE="$2"
        mkdir -p "$WORKSPACE"
        
        # Create default config
        cat <<'CONFIG' > "$WORKSPACE/config.yml"
workingDirectory: workspace
specs:
  dir: workspace/specs
jobs:
  dir: workspace/jobs
CONFIG
        
        # Create workspace directories
        mkdir -p "$WORKSPACE/workspace/specs"
        mkdir -p "$WORKSPACE/workspace/jobs"
        mkdir -p "$WORKSPACE/workspace/wds"
        mkdir -p "$WORKSPACE/workspace/users"
        
        # Create demo spec if requested
        if [ "$3" = "--demo" ]; then
            mkdir -p "$WORKSPACE/workspace/specs/echo"
            cat <<'SPEC' > "$WORKSPACE/workspace/specs/echo/spec.yml"
name: Echo Demo
description: A simple echo demo job
expectedInputs:
  - id: message
    type: string
    name: Message
    description: The message to echo
execution:
  application: echo
  arguments:
    - "${inputs.message}"
SPEC
        fi
        
        echo "Workspace created at $WORKSPACE"
        ;;
        
    serve)
        # Start the Rails server
        CONFIG_FILE="${2:-config.yml}"
        
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "Error: Config file $CONFIG_FILE not found"
            echo "Run 'jobson new .' to create a workspace in the current directory"
            exit 1
        fi
        
        # Set workspace path from current directory
        export JOBSON_WORKSPACE="$(pwd)/workspace"
        
        # Ensure workspace directories exist
        mkdir -p "$JOBSON_WORKSPACE/specs"
        mkdir -p "$JOBSON_WORKSPACE/jobs"
        mkdir -p "$JOBSON_WORKSPACE/wds"
        mkdir -p "$JOBSON_WORKSPACE/users"
        
        cd "$JOBSON_DIR"
        
        # Install dependencies if needed
        if [ ! -d "vendor/bundle" ]; then
            echo "Installing dependencies..."
            bundle config set --local deployment 'true'
            bundle config set --local path 'vendor/bundle'
            bundle install --quiet
        fi
        
        # Start Rails server on port 8080
        bundle exec rails server -b 0.0.0.0 -p 8080 -e production
        ;;
        
    *)
        echo "Usage: jobson {new|serve} [options]"
        echo "  new <dir> [--demo]  Create a new Jobson workspace"
        echo "  serve [config.yml]  Start the Jobson server"
        exit 1
        ;;
esac
EOF

chmod 755 "target/jobson-deb-${VERSION}/usr/bin/jobson"

echo "Rails app packaged for version ${VERSION}"