#!/bin/bash

set -e

VERSION=${1:?Usage: $0 <version>}

TARGET_DIR="target/jobson-deb-${VERSION}"
JOBSON_SHARE_DIR="${TARGET_DIR}/usr/share/jobson"
BIN_DIR="${TARGET_DIR}/usr/bin"

# Clean and prepare directory structure
rm -rf "${TARGET_DIR}"
mkdir -p "${JOBSON_SHARE_DIR}" "${BIN_DIR}"

# Copy Rails app
cp -r ../jobson/src-rails/* "${JOBSON_SHARE_DIR}/"

# Remove development artifacts
for dir in tmp log storage workspace .byebug_history; do
    rm -rf "${JOBSON_SHARE_DIR}/${dir}"
done

# Create jobson command wrapper
create_jobson_wrapper() {
    cat > "${BIN_DIR}/jobson" <<'WRAPPER_SCRIPT'
#!/bin/bash

set -e

JOBSON_DIR="/usr/share/jobson"

ensure_bundler() {
    if ! command -v bundle &> /dev/null; then
        echo "Error: bundler is not installed. Please install it with: gem install bundler"
        exit 1
    fi
}

create_workspace() {
    local workspace="${1:?Usage: jobson new <workspace_dir> [--demo]}"
    local demo_flag="$2"
    
    mkdir -p "${workspace}"
    
    # Create default config
    cat > "${workspace}/config.yml" <<'CONFIG'
workingDirectory: workspace
specs:
  dir: workspace/specs
jobs:
  dir: workspace/jobs
CONFIG
    
    # Create workspace structure
    local dirs=(
        "workspace/specs"
        "workspace/jobs"
        "workspace/wds"
        "workspace/users"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "${workspace}/${dir}"
    done
    
    # Create demo spec if requested
    if [[ "${demo_flag}" == "--demo" ]]; then
        create_demo_spec "${workspace}"
    fi
    
    echo "Workspace created at ${workspace}"
}

create_demo_spec() {
    local workspace="$1"
    local spec_dir="${workspace}/workspace/specs/echo"
    
    mkdir -p "${spec_dir}"
    cat > "${spec_dir}/spec.yml" <<'SPEC'
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
}

start_server() {
    local config="${1:-config.yml}"
    
    if [[ ! -f "${config}" ]]; then
        echo "Error: Config file ${config} not found"
        echo "Run 'jobson new .' to create a workspace in the current directory"
        exit 1
    fi
    
    # Set workspace path from current directory
    export JOBSON_WORKSPACE="$(pwd)/workspace"
    
    # Ensure workspace directories exist
    local dirs=(specs jobs wds users)
    for dir in "${dirs[@]}"; do
        mkdir -p "${JOBSON_WORKSPACE}/${dir}"
    done
    
    cd "${JOBSON_DIR}"
    
    # Install dependencies if needed
    if [[ ! -d "vendor/bundle" ]]; then
        echo "Installing dependencies..."
        bundle config set --local deployment 'true'
        bundle config set --local path 'vendor/bundle'
        bundle install --quiet
    fi
    
    # Start Rails server
    bundle exec rails server -b 0.0.0.0 -p 8080 -e production
}

print_usage() {
    cat <<USAGE
Usage: jobson {new|serve} [options]
  new <dir> [--demo]  Create a new Jobson workspace
  serve [config.yml]  Start the Jobson server
USAGE
}

# Main command handler
ensure_bundler

case "$1" in
    new)
        shift
        create_workspace "$@"
        ;;
    serve)
        shift
        start_server "$@"
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
WRAPPER_SCRIPT

    chmod 755 "${BIN_DIR}/jobson"
}

create_jobson_wrapper

echo "Rails app packaged for version ${VERSION}"