# Stage 1: The "Builder" Stage
FROM jc21/nginx-proxy-manager:latest AS builder

# Switch to root for installation
USER root

# Install all dependencies needed for the build
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    gettext \
    lua-cjson \
    && rm -rf /var/lib/apt/lists/*

# Download the latest CrowdSec Nginx bouncer and run install script
RUN BOUNCER_URL=$(curl -s https://api.github.com/repos/crowdsecurity/cs-nginx-bouncer/releases/latest | grep "browser_download_url.*tgz" | cut -d '"' -f 4) && \
    curl -L $BOUNCER_URL -o /tmp/crowdsec-nginx-bouncer.tgz && \
    tar xzvf /tmp/crowdsec-nginx-bouncer.tgz -C /tmp/ && \
    cd /tmp/crowdsec-nginx-bouncer-v* && \
    CI_MODE=true ./install.sh && \
    rm -rf /tmp/*

# Stage 2: The Final Image
FROM jc21/nginx-proxy-manager:latest

# Switch to root for setup
USER root

# Install runtime dependencies (keep bash - it's likely needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    gettext \
    lua-cjson \
    && rm -rf /var/lib/apt/lists/*

# Create a dedicated non-root user if the base image doesn't have one
# Check what user the base image uses - you might not need this
RUN id 1000 >/dev/null 2>&1 || (groupadd -g 1000 appuser && useradd -u 1000 -g 1000 -m appuser)

# Copy files from builder and set appropriate ownership for non-root user
COPY --from=builder --chown=1000:1000 /etc/nginx/conf.d/crowdsec_nginx.conf /etc/nginx/conf.d/crowdsec_nginx.conf
COPY --from=builder --chown=1000:1000 /etc/crowdsec/bouncers/ /etc/crowdsec/bouncers/
COPY --from=builder --chown=1000:1000 /usr/local/lua/crowdsec/ /usr/local/lua/crowdsec/
COPY --from=builder --chown=1000:1000 /var/lib/crowdsec/lua/ /var/lib/crowdsec/lua/

# Copy any additional binaries (keep as root-owned since they're in system paths)
COPY --from=builder /usr/local/bin/crowdsec* /usr/local/bin/ 2>/dev/null || true

# Ensure the non-root user has access to necessary directories
RUN chown -R 1000:1000 /etc/crowdsec /var/lib/crowdsec /usr/local/lua/crowdsec 2>/dev/null || true

# Switch back to non-root user (this is the key line you were missing!)
USER 1000
