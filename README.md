# Claude Container

A Docker devcontainer for running Claude Code in a sandboxed environment with:
- Node.js 20
- Java 21 (Eclipse Temurin)
- Playwright with headless Chromium (arm64/amd64)
- GitHub CLI with PAT authentication
- Domain-whitelist firewall (default deny)
- Configurable Claude config directory for subscription authentication

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

## Quick Start

### Build the Image

```bash
docker build -t claude-container .devcontainer/
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

1. Open this repository in VS Code
2. Install the "Dev Containers" extension
3. Run **"Dev Containers: Reopen in Container"** from the command palette

## Firewall Configuration

The container uses a domain-whitelist firewall that blocks all outbound traffic except to approved domains. A default whitelist is baked into the image at `/usr/local/etc/allowed-domains.conf`.

### Default Allowed Domains

- `api.anthropic.com` - Claude API
- `registry.npmjs.org` - NPM packages
- `github.com`, `api.github.com` - GitHub
- `repo1.maven.org`, `repo.maven.apache.org` - Maven Central
- `playwright.azureedge.net` - Playwright browser downloads
- VS Code marketplace domains

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
| `TZ` | Timezone (default: `America/Los_Angeles`) |
| `CLAUDE_CODE_VERSION` | Claude Code version to install (default: `latest`) |

## Rebuilding

After modifying the Dockerfile:

```bash
# Docker Compose
docker compose build --no-cache

# Docker directly
docker build --no-cache -t claude-container .devcontainer/
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
