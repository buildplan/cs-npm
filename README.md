# Nginx Proxy Manager with Integrated CrowdSec Bouncer

This repository provides the necessary files to build a custom, multi-architecture Docker image of Nginx Proxy Manager (NPM) that includes the CrowdSec Nginx Bouncer.

The included GitHub Actions workflow automates the process of building and pushing the image to the GitHub Container Registry (GHCR).

## Features

* **Nginx Proxy Manager**: Based on the official `jc21/nginx-proxy-manager:latest` image.
* **CrowdSec Integration**: Includes the official CrowdSec Nginx Bouncer for proactive security.
* **Automated Builds**: A GitHub Actions workflow builds and pushes the image on every commit to the `main` branch.
* **Multi-Architecture**: Builds for both `linux/amd64` and `linux/arm64` architectures.
* **Automated Tagging**: The image is tagged with `latest` and the corresponding NPM version tag (e.g., `v2.12.6`).

## Files in this Repository

### `Dockerfile`

This file defines the steps to build the custom image. It uses the official NPM image as a base, installs the bouncer's dependencies, and then downloads and runs the bouncer's installation script.

```dockerfile
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
RUN BOUNCER_URL=$(curl -s [https://api.github.com/repos/crowdsecurity/cs-nginx-bouncer/releases/latest](https://api.github.com/repos/crowdsecurity/cs-nginx-bouncer/releases/latest) | grep "browser_download_url.*tgz" | cut -d '"' -f 4) && \
    curl -L $BOUNCER_URL -o /tmp/crowdsec-nginx-bouncer.tgz && \
    tar xzvf /tmp/crowdsec-nginx-bouncer.tgz -C /tmp/ && \
    cd /tmp/crowdsec-nginx-bouncer-v* && \
    ./install.sh && \
    rm -rf /tmp/*

# Switch back to the default user
USER 1000
````

### `.github/workflows/build-and-push.yml`

This GitHub Actions workflow automates the build and push process. It triggers on pushes to the `main` branch or can be run manually.

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Get latest NPM version tag
        id: get_version
        run: |
          VERSION=$(curl -s "[https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest](https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest)" | grep -Po '"tag_name": "\K.*?(?=")')
          echo "NPM_VERSION=${VERSION}" >> $GITHUB_ENV

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ env.NPM_VERSION }}
```

## How to Deploy

This guide details how to run the custom NPM container alongside the official CrowdSec agent using Docker Compose.

### 1\. Project Setup

First, create a project directory on your Docker host and a dedicated Docker network for the containers to communicate.

```bash
# Create and enter a new directory
mkdir my-secure-proxy
cd my-secure-proxy

# Create a dedicated Docker network
docker network create crowdsec-net
```

### 2\. Create `docker-compose.yml`

Create a `docker-compose.yml` file in the project directory. Replace `ghcr.io/YOUR-USERNAME/YOUR-REPO-NAME:latest` with the path to the image built by your repository's action.

```yaml
version: '3.8'

services:
  # Service 1: The CrowdSec Security Engine
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    restart: unless-stopped
    environment:
      # Set GID to match log file permissions if necessary
      - GID=999
    volumes:
      # Mount configuration and data directories for persistence
      - ./crowdsec-data/config:/etc/crowdsec/
      - ./crowdsec-data/data:/var/lib/crowdsec/data/
      # Mount host log files for CrowdSec to monitor
      - /var/log/auth.log:/var/log/auth.log:ro
      # This volume will be used for NPM logs
      - /var/log/nginx-proxy-manager:/var/log/npm:ro
    networks:
      - crowdsec-net

  # Service 2: Your Custom Nginx Proxy Manager
  npm:
    # Use the image built from your repository
    image: ghcr.io/YOUR-USERNAME/YOUR-REPO-NAME:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      # Standard NPM data and certs volumes
      - ./npm-data/data:/data
      - ./npm-data/letsencrypt:/etc/letsencrypt
      # Mount a volume for NPM to write its logs to the host
      - /var/log/nginx-proxy-manager:/data/logs
      # Mount a volume for the CrowdSec bouncer configuration
      - ./npm-bouncer-config:/etc/crowdsec/bouncers
    networks:
      - crowdsec-net
    depends_on:
      - crowdsec

networks:
  crowdsec-net:
    external: true
```

### 3\. Generate Bouncer API Key

The NPM bouncer requires an API key to communicate with the CrowdSec agent.

1.  Start the CrowdSec service:
    ```bash
    docker compose up -d crowdsec
    ```
2.  Execute `cscli` inside the running container to add a new bouncer and receive a key:
    ```bash
    docker exec crowdsec cscli bouncers add npm-bouncer
    ```
3.  Copy the generated API key.

### 4\. Create Bouncer Configuration

Create the configuration file that your NPM container will use to connect to CrowdSec.

1.  Create the host directory that will be mounted into the container:
    ```bash
    mkdir npm-bouncer-config
    ```
2.  Create a new file at `npm-bouncer-config/crowdsec-nginx-bouncer.conf.local`.
3.  Add the following content, pasting the API key you generated:
    ```ini
    API_KEY=<PASTE_YOUR_API_KEY_HERE>
    API_URL=http://crowdsec:8080
    ```
    The `API_URL` uses the service name `crowdsec` because both containers share the `crowdsec-net` Docker network.

### 5\. Launch the Stack

Start all services using Docker Compose.

```bash
docker compose up -d
```

### 6\. Verification

Check that the bouncer has successfully connected to the CrowdSec agent.

```bash
docker exec crowdsec cscli bouncers list
```

The output should show `npm-bouncer` in the list with a "validated" status. This may take a minute to update after the initial startup.

```
