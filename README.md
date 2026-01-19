# Claude Container

A Docker devcontainer for running Claude Code in a sandboxed environment with:
- Node.js 20
- Java 21 (Eclipse Temurin)
- GitHub CLI with PAT authentication
- Domain-whitelist firewall (default deny)
- Bind-mounted `~/.claude` for subscription authentication

## Prerequisites

Before running the container, ensure:

1. **Claude subscription credentials** exist at `~/.claude` on your host machine
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
docker-compose up -d && docker-compose exec claude zsh

# Or start and attach directly (container removed on exit)
docker-compose run --rm claude

# Stop the container
docker-compose down
```

### Option 2: Interactive Shell (Docker Run)

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$HOME/.claude:/home/node/.claude:cached" \
  -v "$(pwd):/workspace:delegated" \
  -e GH_TOKEN="$GH_TOKEN" \
  -w /workspace \
  claude-container
```

### Option 3: Run a One-Off Claude Prompt

Execute a single prompt and exit:

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$HOME/.claude:/home/node/.claude:cached" \
  -v "$(pwd):/workspace:delegated" \
  -e GH_TOKEN="$GH_TOKEN" \
  -w /workspace \
  claude-container \
  claude -p "Your prompt here"
```

**Example - Ask Claude to explain a file:**

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$HOME/.claude:/home/node/.claude:cached" \
  -v "$(pwd):/workspace:delegated" \
  -w /workspace \
  claude-container \
  claude -p "Explain what this project does based on the files in /workspace"
```

**Example - Generate code:**

```bash
docker run -it --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$HOME/.claude:/home/node/.claude:cached" \
  -v "$(pwd):/workspace:delegated" \
  -w /workspace \
  claude-container \
  claude -p "Create a hello world Python script in /workspace/hello.py"
```

## VS Code Dev Container

1. Open this repository in VS Code
2. Install the "Dev Containers" extension
3. Run **"Dev Containers: Reopen in Container"** from the command palette

## Firewall Configuration

The container uses a domain-whitelist firewall that blocks all outbound traffic except to approved domains.

**View allowed domains:**
```bash
cat .devcontainer/allowed-domains.conf
```

**Add a new domain:**
1. Edit `.devcontainer/allowed-domains.conf`
2. Run `firewall-reload` inside the container

**Check firewall status:**
```bash
firewall-status
```

### Default Allowed Domains

- `api.anthropic.com` - Claude API
- `registry.npmjs.org` - NPM packages
- `github.com`, `api.github.com` - GitHub
- `repo1.maven.org` - Maven Central
- VS Code marketplace domains

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GH_TOKEN` | GitHub Personal Access Token for `gh` CLI authentication |
| `TZ` | Timezone (default: `America/Los_Angeles`) |
| `CLAUDE_CODE_VERSION` | Claude Code version to install (default: `latest`) |

## Rebuilding

After modifying the Dockerfile:

```bash
# Docker Compose
docker-compose build --no-cache

# Docker directly
docker build --no-cache -t claude-container .devcontainer/
```
