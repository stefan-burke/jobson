FROM ubuntu:24.04

# Set non-interactive to avoid timezone prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install 3rd-party dependencies
RUN apt update && apt install -y \
    nginx \
    ruby \
    ruby-dev \
    build-essential \
    libyaml-dev \
    supervisor \
    bundler

# Install jobson debian package
COPY target/jobson.deb /tmp
RUN dpkg -i /tmp/jobson.deb
RUN rm /tmp/jobson.deb

# Configure nginx
COPY default.conf /etc/nginx/conf.d/default.conf
RUN rm -rf /etc/nginx/sites-enabled/default

# Configure supervisord
COPY supervisord.conf /etc/supervisord.conf

# Configure OS to have a 'jobson' account
RUN groupadd -r jobson && useradd --no-log-init -r -g jobson jobson
RUN mkdir -p /home/jobson && chown jobson:jobson /home/jobson

# Pre-install bundle dependencies as root (for the shared app)
RUN cd /usr/share/jobson && \
    bundle config set --local deployment 'true' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install

# Configure 'jobson' account with a jobson workspace
USER jobson
RUN cd /home/jobson && jobson new . --demo
USER root

# Ensure jobson user can write to necessary directories
RUN mkdir -p /usr/share/jobson/tmp /usr/share/jobson/log /usr/share/jobson/workspace && \
    chown -R jobson:jobson /usr/share/jobson

EXPOSE 80
CMD ["supervisord", "--configuration", "/etc/supervisord.conf", "--nodaemon"]
