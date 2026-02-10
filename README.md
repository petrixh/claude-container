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

This repository provides three container variants:

| Variant | Size | Docker | Best For | Limitations |
|---------|------|--------|----------|-------------|
| **`claude`** (base) ⭐ | 3.47GB | ❌ No | General Claude Code development | No Docker support |
| **`claude-docker-host`** | 3.92GB | ✅ Via host | Docker development, testing | Requires host Docker |
| **`claude-dind`** | 3.92GB | ✅ Isolated | Secure isolation, CI/CD | Firewall blocks Docker Hub |

### Quick Decision Guide

**Choose `claude` (base) if:** ⭐ RECOMMENDED
- General development (Java, Node.js, etc.)
- You don't need Docker inside the container
- You want the smallest, fastest container

**Choose `claude-docker-host` if:**
- You need Docker and have Docker on your host
- You want to pull from Docker Hub
- You want lower resource usage than DinD

**Choose `claude-dind` if:**
- You need complete isolation from host Docker
- You're testing untrusted code
- You're willing to work around firewall limitations

## Quick Start

### Most Common Use Cases

**Standard Development (recommended):**
```bash
docker compose up -d claude
docker compose exec claude zsh
claude --version
```

**Docker Development (host socket):**
```bash
docker compose up -d claude-docker-host
docker compose exec claude-docker-host zsh
docker pull alpine  # Works without firewall issues!
```

**Isolated Docker Environment:**
```bash
docker compose up -d claude-dind
docker compose exec claude-dind zsh
# Note: Docker Hub pulls blocked by firewall - see Known Limitations
```

### Build the Images

```bash
# Base variant (default)
docker build -t claude-container:base --target base .devcontainer/

# DinD variant (both claude-dind and claude-docker-host use this)
docker build -t claude-container:dind --target dind .devcontainer/
```

### Interactive Shell Options

#### Option 1: Docker Compose (Recommended)

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
  -v "/path/to/claude-container-config:/home/node/.claude" \
  -e CLAUDE_CONFIG_DIR="/home/node/.claude" \
  -w /workspace \
  claude-container:base
```

> **Note:** The `CLAUDE_CONFIG_DIR` environment variable tells Claude where to store authentication credentials. Mount a host directory to persist login across container restarts.

### Option 2b: Docker Run with Environment File

For easier management of environment variables, use a `.env` file:

```bash
# Copy the example env file and edit with your settings
cp .env.example .env
vim .env

# Minimal: just env file
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  claude-container:base
```

**Add Maven cache** to avoid re-downloading dependencies:

```bash
mkdir -p ~/.m2-cache

docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.m2-cache:/home/node/.m2" \
  claude-container:base
```

**Add workspace** to work on a project:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.m2-cache:/home/node/.m2" \
  -v "$(pwd):/workspace" \
  claude-container:base
```

**Full setup** with all common mounts:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --env-file .env \
  -v "${HOME}/.claude:/home/node/.claude" \
  -v "${HOME}/.m2-cache:/home/node/.m2" \
  -v "${HOME}/.npm-cache:/home/node/.npm" \
  -v "${HOME}/.config/gh:/home/node/.config/gh" \
  -v "$(pwd):/workspace" \
  -p 9222:9222 \
  claude-container:base
```

**Volume mounts explained:**

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `~/.claude` | `/home/node/.claude` | Claude authentication and config |
| `~/.m2-cache` | `/home/node/.m2` | Maven local repository cache |
| `~/.npm-cache` | `/home/node/.npm` | NPM cache |
| `~/.config/gh` | `/home/node/.config/gh` | GitHub CLI authentication |
| `$(pwd)` | `/workspace` | Your project directory |

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

> **⚠️ Important:** The `claude-dind` variant's firewall blocks Docker Hub image pulls due to dynamic CDN domains. For Docker development with image pulling, use the `claude-docker-host` variant instead. See [Known Limitations](#known-limitations-and-workarounds) for details.

### When to Use Each Variant

**Base Variant (`claude`)** ⭐ Recommended
- ✅ Standard Claude Code development
- ✅ Smallest image size (3.47GB)
- ✅ Fastest startup (~2 seconds)
- ✅ Lowest resource usage
- Use when: General development without Docker needs (most users)

**Host Socket Variant (`claude-docker-host`)** - For Docker development
- ✅ Access to Docker without firewall issues
- ✅ Shares host Docker daemon and images
- ✅ Lower resource usage than separate daemon
- ✅ No privileged mode required
- ⚠️  Can affect host Docker state
- ⚠️  Requires host Docker installation
- Use when: You need Docker and trust your environment

**Separate Daemon Variant (`claude-dind`)** - For isolated environments
- ✅ Full isolation from host Docker
- ✅ Persistent Docker cache in container
- ✅ Works without host Docker
- ⚠️  Requires privileged mode
- ⚠️  Higher resource usage (+100-200MB RAM)
- ⚠️  Docker Hub pulls blocked by firewall
- ⚠️  Slower startup (~8 seconds)
- Use when: You need isolated Docker or untrusted code testing

### Testing Docker Inside Container

```bash
# Enter DinD container
docker compose exec claude-dind zsh

# Verify Docker installation
docker version
docker compose version

# Note: Docker Hub image pulls may be blocked by firewall
# See "Known Limitations" section below for workarounds
```

### Known Limitations and Workarounds

#### Docker Hub Image Pulls with Firewall

**Issue:** Docker Hub now uses Cloudflare R2 storage with dynamic subdomains that cannot be whitelisted by domain name. Image pulls will timeout when the firewall is enabled.

**Symptoms:**
```
failed to do request: Get "https://docker-images-prod.*.r2.cloudflarestorage.com/...":
dial tcp 172.64.66.1:443: i/o timeout
```

**Workarounds:**

**Option 1: Disable Firewall for DinD Container**
```bash
# Method A: Skip firewall initialization
docker run -it --rm --privileged \
  -e SKIP_FIREWALL=1 \
  claude-container:dind

# Method B: Run with permissive OUTPUT policy
docker run -it --rm --privileged \
  claude-container:dind bash -c \
  "sudo iptables -P OUTPUT ACCEPT && exec zsh"
```

**Option 2: Use Host Docker Socket (Recommended)**

The `claude-docker-host` variant mounts the host's Docker socket, bypassing the firewall issue:
```bash
docker compose up -d claude-docker-host
docker compose exec claude-docker-host zsh

# Now use host's Docker (images, containers shared with host)
docker pull alpine
docker images  # Shows host images
```

**Option 3: Pre-pull Images on Host**

Pull images on your host machine, then they're available inside DinD:
```bash
# On host
docker pull alpine:latest
docker pull node:20

# In claude-docker-host container
docker images  # Images available immediately
```

**Option 4: Use Local/Private Registry**

Configure a local or private registry with known domain names:
```bash
# Add your registry to allowed-domains.conf
echo "registry.mycompany.com" >> .devcontainer/allowed-domains.conf

# Rebuild and use
docker pull registry.mycompany.com/myimage:latest
```

**Option 5: Build Images Locally**

Build images inside the container without pulling from Docker Hub:
```bash
# Inside DinD container
cat > Dockerfile <<'EOF'
FROM scratch
COPY ./myapp /app
CMD ["/app/myapp"]
EOF

docker build -t myapp:latest .
docker run myapp:latest
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
| `SKIP_FIREWALL` | Set to `1` to skip firewall initialization (useful for DinD troubleshooting) |
| `FIREWALL_CONFIG` | Custom path to allowed-domains.conf (default: workspace or `/usr/local/etc`) |
| `DOCKER_HOST` | Docker daemon socket (default: `unix:///var/run/docker.sock`) |
| `PLAYWRIGHT_BROWSERS_PATH` | Path to pre-installed Playwright browsers (default: `/opt/playwright-browsers`) |
| `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` | Set to `1` to skip browser downloads (default: `1`, browsers are pre-installed) |
| `PLAYWRIGHT_CHROMIUM_DEBUG_PORT` | Enable Playwright CDP debugging on specified port (e.g., `9222`). Empty = disabled |
| `VAADIN_PRO_KEY` | Vaadin Pro/Commercial subscription key for commercial components (Charts, Board, etc.) and Acceleration Kits |

## Vaadin Commercial Components

The container supports [Vaadin commercial components](https://vaadin.com/components) (Charts, Board, Grid Pro, etc.) and Acceleration Kits via the `VAADIN_PRO_KEY` environment variable.

### Providing the Pro Key

There are two ways to provide your Vaadin Pro subscription key:

**Option 1: Environment variable (recommended for containers)**

Set `VAADIN_PRO_KEY` in your `.env` file or pass it directly:
```bash
# In .env file
VAADIN_PRO_KEY=your-pro-key-here

# Or via docker run
docker run -it --rm \
  -e VAADIN_PRO_KEY=your-pro-key-here \
  claude-container:base
```

When the container starts, the entrypoint automatically writes the key to `~/.vaadin/proKey` so both the environment variable and file-based mechanisms work.

**Option 2: Mount a proKey file**

If you already have a `~/.vaadin/proKey` file on your host, mount it into the container:
```bash
docker run -it --rm \
  -v "${HOME}/.vaadin:/home/node/.vaadin:ro" \
  claude-container:base
```

### Firewall Domains

If you're using Vaadin commercial components with the firewall enabled, uncomment the Vaadin domains in `allowed-domains.conf`:
```
maven.vaadin.com
tools.vaadin.com
vaadin.com
cdn.vaadin.com
```

Or add them at runtime:
```bash
# Inside the container
echo -e "maven.vaadin.com\ntools.vaadin.com\nvaadin.com\ncdn.vaadin.com" | sudo tee -a /usr/local/etc/allowed-domains.conf
firewall-reload
```

## Playwright

The container includes Playwright with Chromium pre-installed, ready to use with both Node.js and Java Playwright libraries.

### Pre-installed Browsers

The container includes **two versions** of Chromium to support different use cases:

- **Standard Playwright Chromium** (e.g., `chromium-1208`) - For Java Playwright and direct Node.js Playwright usage
- **MCP Playwright Chromium** (e.g., `chromium-1209`) - For Claude's browser automation tools (`@playwright/mcp`)
- **FFmpeg** (for video recording)

This dual installation ensures that Claude's MCP browser tools work without downloading browsers at runtime.

Browsers are installed at `/opt/playwright-browsers` and owned by the `node` user (writable for lock files).

### MCP Configuration (.mcp.json)

To use the pre-installed MCP browsers (avoiding downloads at runtime), pin the `@playwright/mcp` version in your `.mcp.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": [
        "@playwright/mcp@0.0.64",
        "--headless",
        "--browser",
        "chromium"
      ]
    }
  }
}
```

**Key options:**
- `@playwright/mcp@X.X.X` - Pin to the installed version (check with `playwright-info`)
- `--headless` - Run without visible browser UI (recommended for containers)
- `--browser chromium` - Explicitly use Chromium

**Check the installed MCP version:**
```bash
playwright-info
# Shows: MCP Package: @playwright/mcp@0.0.64
```

Using `@latest` instead of a pinned version will download new browsers at runtime, which may be slow or fail if the firewall blocks downloads.

### Java Playwright

The container is configured to work with Java Playwright out of the box:

- `PLAYWRIGHT_BROWSERS_PATH` points to pre-installed browsers
- `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` prevents unnecessary download attempts
- Required GUI libraries (`libgtk-3`, `libXcursor`) are pre-installed

**Important:** Match your Java Playwright version to the container's Playwright version to use pre-installed browsers.

**Check compatibility info:**
```bash
# Inside the container, run:
playwright-info

# Or check the VERSION file directly:
cat /opt/playwright-browsers/VERSION
```

Example output:
```
Standard Playwright: 1.58.1
  Chromium:          chromium-1208

MCP Package:         @playwright/mcp@0.0.64
  Playwright:        1.59.0-alpha
  Chromium:          chromium-1209
```

Use this version in your Maven `pom.xml`:
```xml
<dependency>
    <groupId>com.microsoft.playwright</groupId>
    <artifactId>playwright</artifactId>
    <version>1.58.1</version>  <!-- Match PLAYWRIGHT_VERSION -->
</dependency>
```

### Remote Debugging (CDP)

The container supports Playwright remote debugging via Chrome DevTools Protocol (CDP), allowing you to connect an external Chrome browser to debug Playwright tests running inside the container.

#### How It Works

The Chromium headless shell only binds to localhost, so the container uses `socat` to forward the debug port:
- **External port** (0.0.0.0): `PLAYWRIGHT_CHROMIUM_DEBUG_PORT` (e.g., 9222)
- **Internal port** (127.0.0.1): `PLAYWRIGHT_CDP_INTERNAL_PORT` (automatically set to external + 1, e.g., 9223)

#### Quick Start

1. **Start container with debugging enabled:**
   ```bash
   docker run -it --rm \
     --cap-add=NET_ADMIN \
     --cap-add=NET_RAW \
     -e SKIP_FIREWALL=1 \
     -e PLAYWRIGHT_CHROMIUM_DEBUG_PORT=9222 \
     -p 9222:9222 \
     claude-container:base
   ```

2. **Inside the container, launch Playwright with the internal port (external + 1):**
   ```javascript
   const { chromium } = require('playwright');
   const internalPort = parseInt(process.env.PLAYWRIGHT_CHROMIUM_DEBUG_PORT || '9222') + 1;
   const browser = await chromium.launch({
     args: [`--remote-debugging-port=${internalPort}`]
   });
   ```

3. **Connect from Chrome:**
   - Open Chrome and navigate to `chrome://inspect`
   - Click "Configure..." and add `localhost:9222`
   - Your Playwright browser sessions will appear under "Remote Target"

#### Usage Examples

**Quick test script:**
```bash
node -e "
const { chromium } = require('playwright');
(async () => {
  const internalPort = parseInt(process.env.PLAYWRIGHT_CHROMIUM_DEBUG_PORT || '9222') + 1;
  const browser = await chromium.launch({
    args: ['--remote-debugging-port=' + internalPort]
  });
  const page = await browser.newPage();
  await page.goto('https://example.com');
  console.log('Browser ready on internal port', internalPort, '- connect via chrome://inspect');
  await new Promise(() => {});
})();
"
```

**With docker compose:**
```bash
PLAYWRIGHT_CHROMIUM_DEBUG_PORT=9222 docker compose up -d claude
docker compose exec claude bash  # Then run your Playwright script
```

**With VS Code Dev Container:**
```bash
# Set before opening dev container
export PLAYWRIGHT_CHROMIUM_DEBUG_PORT=9222
```

#### Security Note

Remote debugging exposes browser internals. Only enable when needed and do not expose port 9222 to untrusted networks.

## Troubleshooting

### Docker Hub Pulls Timeout in DinD

**Symptom:** `dial tcp 172.64.66.1:443: i/o timeout` when pulling Docker images

**Solution:** Use the `claude-docker-host` variant instead, or disable the firewall:
```bash
# Recommended: Use host socket variant
docker compose up -d claude-docker-host

# Alternative: Disable firewall in DinD
docker run -it --rm --privileged -e SKIP_FIREWALL=1 claude-container:dind
```

### Docker Daemon Fails to Start

**Symptom:** "Error: Docker daemon failed to start"

**Check logs:**
```bash
# Inside container
cat /var/log/docker.log

# Common issues:
# - Missing privileged mode: Add --privileged flag
# - Missing SYS_ADMIN capability: Add --cap-add=SYS_ADMIN
```

**Solution:** Ensure proper flags:
```bash
docker run --rm --privileged \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --cap-add=SYS_ADMIN \
  claude-container:dind
```

### Firewall Blocking Required Domain

**Symptom:** Connection timeouts or "Could not resolve" warnings

**Check firewall status:**
```bash
# Inside container
firewall-status

# Check if domain is allowed
grep "mydomain.com" /usr/local/etc/allowed-domains.conf
```

**Solution:** Add domain to whitelist:
```bash
# Edit allowed-domains.conf
echo "mydomain.com" >> .devcontainer/allowed-domains.conf

# Rebuild image
docker build -t claude-container:base --target base .devcontainer/

# Or reload firewall at runtime (temporary)
# Inside container:
echo "mydomain.com" | sudo tee -a /usr/local/etc/allowed-domains.conf
firewall-reload
```

### Permission Denied Errors

**Symptom:** "Permission denied" when accessing Docker socket

**For host socket variant:**
```bash
# Ensure your user is in docker group on host
sudo usermod -aG docker $USER
newgrp docker

# Or run container with your user's UID
docker run --rm -u $(id -u):$(getent group docker | cut -d: -f3) \
  -v /var/run/docker.sock:/var/run/docker.sock \
  claude-container:dind
```

### Overlay2 Storage Driver Issues

**Symptom:** "invalid argument" when running nested containers

**Solution:** Use a named volume for `/var/lib/docker`:
```bash
docker run --rm --privileged \
  -v claude-docker-data:/var/lib/docker \
  claude-container:dind
```

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
