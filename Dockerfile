# Use the official Nginx Proxy Manager image as the base
FROM jc21/nginx-proxy-manager:latest

# Switch to root user to install packages
USER root

# Install dependencies and curl to download the bouncer using apt-get for Debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    gettext \
    lua-cjson \
    && rm -rf /var/lib/apt/lists/*

# Download the latest CrowdSec Nginx bouncer, install it, and clean up
RUN BOUNCER_URL=$(curl -s https://api.github.com/repos/crowdsecurity/cs-nginx-bouncer/releases/latest | grep "browser_download_url.*tgz" | cut -d '"' -f 4) && \
    curl -L $BOUNCER_URL -o /tmp/crowdsec-nginx-bouncer.tgz && \
    tar xzvf /tmp/crowdsec-nginx-bouncer.tgz -C /tmp/ && \
    cd /tmp/crowdsec-nginx-bouncer-v* && \
    ./install.sh && \
    rm -rf /tmp/*

# Switch back to the default user
USER 1000
