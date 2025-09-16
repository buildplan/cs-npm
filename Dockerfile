# Use the official Nginx Proxy Manager image as the base
FROM jc21/nginx-proxy-manager:latest

# Switch to root user to install packages
USER root

# Install dependencies and curl to download the bouncer
RUN apk add --no-cache bash curl gettext lua5.1-cjson

# Download the latest CrowdSec Nginx bouncer, install it, and clean up
RUN BOUNCER_URL=$(curl -s https://api.github.com/repos/crowdsecurity/cs-nginx-bouncer/releases/latest | grep "browser_download_url.*tgz" | cut -d '"' -f 4) && \
    curl -L $BOUNCER_URL -o /tmp/crowdsec-nginx-bouncer.tgz && \
    tar xzvf /tmp/crowdsec-nginx-bouncer.tgz -C /tmp/ && \
    cd /tmp/crowdsec-nginx-bouncer-v* && \
    ./install.sh && \
    rm -rf /tmp/*

# Switch back to the default user
USER 1000
