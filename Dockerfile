# Stage 1: The "Builder" Stage
# This stage has a complete environment to ensure the install script runs correctly.
FROM jc21/nginx-proxy-manager:latest AS builder

# Switch to root to install packages and the bouncer
USER root

# Install all dependencies needed for the build AND for the script to run
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gettext \
    lua-cjson \
    && rm -rf /var/lib/apt/lists/*

# Download the latest CrowdSec Nginx bouncer, and run the install script
# The "CI_MODE=true" flag forces a non-interactive installation.
RUN BOUNCER_URL=$(curl -s https://api.github.com/repos/crowdsecurity/cs-nginx-bouncer/releases/latest | grep "browser_download_url.*tgz" | cut -d '"' -f 4) && \
    curl -L $BOUNCER_URL -o /tmp/crowdsec-nginx-bouncer.tgz && \
    tar xzvf /tmp/crowdsec-nginx-bouncer.tgz -C /tmp/ && \
    cd /tmp/crowdsec-nginx-bouncer-v* && \
    CI_MODE=true ./install.sh && \
    rm -rf /tmp/*


# Stage 2: The Final Image
# This is the lean, final image.
FROM jc21/nginx-proxy-manager:latest

# Switch to root to install only the runtime dependencies and copy files
USER root

# Install ONLY the runtime dependencies for the bouncer. Notice 'curl' is omitted.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gettext \
    lua-cjson \
    && rm -rf /var/lib/apt/lists/*

# Copy only the necessary installed files from the "builder" stage
COPY --from=builder /etc/nginx/conf.d/crowdsec_nginx.conf /etc/nginx/conf.d/crowdsec_nginx.conf
COPY --from=builder /etc/crowdsec/bouncers/ /etc/crowdsec/bouncers/
COPY --from=builder /usr/local/lua/crowdsec/ /usr/local/lua/crowdsec/
COPY --from=builder /var/lib/crowdsec/lua/ /var/lib/crowdsec/lua/
