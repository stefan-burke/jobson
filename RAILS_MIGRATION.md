# Jobson Rails Migration

This document describes the migration from Java to Rails for the Jobson backend.

## What Changed

### Backend
- **Removed**: Java backend (`jobson/src/main/java`)
- **Added**: Rails API backend (`jobson/src-rails`)
- **Preserved**: Exact same REST API endpoints and WebSocket channels
- **Preserved**: File-based storage (no database required)

### Dependencies
- **Removed**: Java (JRE/JDK)
- **Added**: Ruby 3.0+ and Bundler
- **Simplified**: No Redis, no database, no mail server

### Packaging

#### Debian Package (`jobson-deb/`)
- Updated to package Rails app instead of Java JAR
- Dependencies changed from `default-jre` to `ruby (>= 3.0)` and `bundler`
- New script: `repackage-rails-app.sh` replaces the Java packaging

#### Docker (`jobson-docker/`)
- Base image includes Ruby instead of Java
- Installs Ruby gems with bundler
- Pre-compiles Rails assets and dependencies

### API Compatibility
- All REST endpoints remain identical
- WebSocket channels for real-time updates preserved
- Web UI continues to work without modifications

## Building and Running

### Standalone Docker
```bash
docker build -t jobson-rails .
docker run -p 8080:8080 jobson-rails
```

### Debian Package
```bash
cd jobson-deb
./repackage-rails-app.sh 1.0.14
./make-deb-pkg.sh 1.0.14
```

### Development
```bash
cd jobson/src-rails
bundle install
bundle exec rails server -p 8080
```

## Testing

Run API compatibility tests:
```bash
./test_api_compatibility.sh
```

All 28 tests should pass, confirming the Rails backend is a drop-in replacement.

## Key Features Preserved

1. **File-based storage** - No database required
2. **WebSocket support** - Real-time job status and output streaming
3. **No authentication** - Suitable for trusted LAN environments
4. **Job execution** - Background job processing with live output
5. **API compatibility** - Exact same endpoints as Java version

## Architecture

```
Web UI (unchanged) 
    ↓
Nginx (reverse proxy)
    ↓
Rails API (port 8080)
    ↓
File System (workspace/)
```

The Rails app uses:
- **ActionCable** for WebSocket connections
- **ActiveJob** with async adapter for background processing
- **File-based storage** for jobs, specs, and outputs
- **No database** - all data in filesystem