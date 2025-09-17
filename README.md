# Nginx Proxy Manager with Integrated CrowdSec Bouncer

Nginx Proxy Manager (NPM) that includes the CrowdSec Nginx Bouncer.

GitHub Actions workflow automates the process of building and pushing the image to the GitHub Container Registry (GHCR).

## Features

* **Nginx Proxy Manager**: Based on the official `jc21/nginx-proxy-manager:latest` image.
* **CrowdSec Integration**: Includes the official CrowdSec Nginx Bouncer for proactive security.
* **Automated Builds**: A GitHub Actions workflow builds and pushes the image on every commit to the `main` branch.
* **Multi-Architecture**: Builds for both `linux/amd64` and `linux/arm64` architectures.
* **Automated Tagging**: The image is tagged with `latest` and the corresponding NPM version tag (e.g., `v2.12.6`).

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
services:
  # Service 1: The CrowdSec Security Engine
  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    restart: unless-stopped
    environment:
      # Match the GID of your log files for permission to read them
      - GID=999
    volumes:
      # Persist CrowdSec configuration and data
      - ./crowdsec/config:/etc/crowdsec/
      - ./crowdsec/data:/var/lib/crowdsec/data/
      # Example: Mount host ssh logs to be monitored by CrowdSec
      - /var/log/auth.log:/var/log/auth.log:ro
      # Mount the NPM log directory for CrowdSec to read
      - ./npm/logs:/var/log/npm:ro
    networks:
      - cs-npm-net

  # Service 2: Your Custom Nginx Proxy Manager with Bouncer
  npm:
    # IMPORTANT: Replace with your image path from your container registry
    image: ghcr.io/buildplan/cs-npm:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - '80:80'    # Public HTTP Port
      - '443:443'  # Public HTTPS Port
      - '81:81'    # Admin UI Port
    environment:
      # Set the User and Group ID for file permissions.
      # Find your ID on the host with `id -u` and `id -g`
      - PUID=1000
      - PGID=1000
    volumes:
      # Main data volume for NPM configs, users, SSL certs, etc.
      - ./npm/data:/data
      # For letsencrypt certs
      - ./npm/data/letsencrypt:/etc/letsencrypt
      # Maps the internal log directory to the host so CrowdSec can see it
      - ./npm/logs:/data/logs
      # Maps the bouncer configuration file into the container
      - ./npm/cs-bouncer-config:/etc/crowdsec/bouncers
    networks:
      - cs-npm-net
    depends_on:
      - crowdsec

# Defines the network used by both services for communication
networks:
  cs-npm-net:
    driver: bridge
    name: cs-npm-net
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
