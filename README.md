# Claude Container

A Docker devcontainer for running Claude Code in a sandboxed environment with:
- Node.js 20
- Java 21 (Eclipse Temurin)
- Playwright with headless Chromium (arm64/amd64)
- GitHub CLI with PAT authentication
- Domain-whitelist firewall (default deny)
- Configurable Claude config directory for subscription authentication
- Optional Docker-in-Docker (DinD) support for containerized development

## Prerequisites

Before running the container, ensure:

1. **Claude config directory** exists on your Docker host for persisting authentication:
   ```bash
   mkdir -p /path/to/claude-container-config
   ```
2. **GitHub PAT** (optional) - set the `GH_TOKEN` environment variable:
   ```bash
   export GH_TOKEN=ghp_your_token_here
   ```

## Container Variants

This repository provides two container variants:

### Base Variant (Default)
The standard Claude Code container without Docker support. Use this for general development tasks.

### DinD Variant (Docker-in-Docker)
Includes Docker CLI and daemon for containerized development workflows. Choose between:
- **Separate daemon** (`claude-dind`): Runs isolated Docker daemon inside container
- **Host socket** (`claude-docker-host`): Mounts host Docker socket for shared resources

## Quick Start

### Build the Image

```bash
# Base variant (default)
docker build -t claude-container:base --target base .devcontainer/

# DinD variant
docker build -t claude-container:dind --target dind .devcontainer/
```

### Option 1: Interactive Shell (Docker Compose)

Start an interactive development environment:

```bash
# Start container in background and attach
docker compose up -d && docker compose exec claude zsh

# Or start and attach directly (container removed on exit)
docker compose run --rm claude

# Stop the container
docker compose down

# DinD variant with separate Docker daemon
docker compose up -d claude-dind && docker compose exec claude-dind zsh

# DinD variant mounting host Docker socket
docker compose up -d claude-docker-host && docker compose exec claude-docker-host zsh
```

### Option 2: Interactive Shell (Docker Run)

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/path/to/claude-container-config:/claude-container-config" \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  -w /workspace \
  claude-container
```

> **Note:** The `CLAUDE_CONFIG_DIR` environment variable tells Claude where to store authentication credentials. Mount a host directory to persist login across container restarts.

### Option 3: Run a One-Off Claude Prompt

Execute a single prompt and exit:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/path/to/claude-container-config:/claude-container-config" \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  -w /workspace \
  claude-container \
  claude -p "Your prompt here"
```

## VS Code Dev Container

### Base Variant
1. Open this repository in VS Code
2. Install the "Dev Containers" extension
3. Run **"Dev Containers: Reopen in Container"** from the command palette

### DinD Variant
Use the alternative configuration for Docker-in-Docker support:

```bash
# Using devcontainer CLI
devcontainer up --workspace-folder . \
  --config .devcontainer/devcontainer-dind.json

# Or rename the config (backup original first)
mv .devcontainer/devcontainer.json .devcontainer/devcontainer-base.json
mv .devcontainer/devcontainer-dind.json .devcontainer/devcontainer.json
```

## Docker-in-Docker Usage

### When to Use Each Variant

**Separate Daemon (`claude-dind`)**
- Full isolation from host Docker
- Persistent Docker cache in container
- Requires privileged mode
- Higher resource usage

**Host Socket (`claude-docker-host`)**
- Shares host Docker daemon
- Lower resource usage
- Simpler setup
- Can affect host Docker state

### Testing Docker Inside Container

```bash
# Enter DinD container
docker compose exec claude-dind zsh

# Verify Docker installation
docker version
docker compose version

# Pull and run test image
docker pull hello-world
docker run hello-world

# Build a test image
echo 'FROM alpine' > Dockerfile.test
echo 'RUN echo "test"' >> Dockerfile.test
docker build -f Dockerfile.test -t test .
docker run test
```

## Firewall Configuration

The container uses a domain-whitelist firewall that blocks all outbound traffic except to approved domains. A default whitelist is baked into the image at `/usr/local/etc/allowed-domains.conf`.

### Default Allowed Domains

- `api.anthropic.com` - Claude API
- `registry.npmjs.org` - NPM packages
- `github.com`, `api.github.com` - GitHub
- `repo1.maven.org`, `repo.maven.apache.org` - Maven Central
- `playwright.azureedge.net` - Playwright browser downloads
- VS Code marketplace domains
- `registry-1.docker.io`, `auth.docker.io` - Docker Hub (DinD variant)

### Customizing the Domain Whitelist

To use your own domain whitelist, bind mount a custom config file:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/path/to/your/allowed-domains.conf:/usr/local/etc/allowed-domains.conf:ro" \
  -v "/path/to/claude-container-config:/claude-container-config" \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  claude-container
```

Or copy the default config and modify it:

```bash
# Copy from this repo
cp .devcontainer/allowed-domains.conf ~/my-allowed-domains.conf

# Edit to add your domains
echo "example.com" >> ~/my-allowed-domains.conf
```

### Runtime Firewall Commands

Inside the container:

```bash
# View current firewall rules
firewall-status

# Reload firewall after editing the config
firewall-reload
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_CONFIG_DIR` | Directory for Claude authentication and config (mount from host for persistence) |
| `GH_TOKEN` | GitHub Personal Access Token for `gh` CLI authentication |
| `TZ` | Timezone (default: `Europe/Helsinki`). Pass `-e TZ=$TZ` to inherit from host |
| `CLAUDE_CODE_VERSION` | Claude Code version to install (default: `latest`) |

## Rebuilding

After modifying the Dockerfile:

```bash
# Docker Compose (base variant)
docker compose build --no-cache claude

# Docker Compose (DinD variants)
docker compose build --no-cache claude-dind
docker compose build --no-cache claude-docker-host

# Docker directly
docker build --no-cache -t claude-container:base --target base .devcontainer/
docker build --no-cache -t claude-container:dind --target dind .devcontainer/
```

## Quick Reference (Docker Remote)

For Docker remote setups where the Docker daemon runs on a separate host, use absolute paths on the Docker host:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "/home/deb/claude-container-config:/claude-container-config" \
  -w /workspace \
  -e CLAUDE_CONFIG_DIR="/claude-container-config" \
  claude-container
```
