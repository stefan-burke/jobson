# Standalone Dockerfile for Jobson Rails
FROM ruby:3.2-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Rails app
COPY jobson/src-rails/ .

# Install Ruby dependencies
RUN bundle config set --local deployment 'true' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install

# Create workspace directory
RUN mkdir -p workspace/specs workspace/jobs workspace/wds workspace/users

# Create a simple echo demo spec
RUN mkdir -p workspace/specs/echo && \
    echo 'name: Echo Demo\n\
description: A simple echo demo job\n\
expectedInputs:\n\
  - id: message\n\
    type: string\n\
    name: Message\n\
    description: The message to echo\n\
execution:\n\
  application: echo\n\
  arguments:\n\
    - "${inputs.message}"' > workspace/specs/echo/spec.yml

# Expose Rails port
EXPOSE 8080

# Set Rails environment
ENV RAILS_ENV=production
ENV JOBSON_WORKSPACE=/app/workspace

# Start Rails server
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "8080"]