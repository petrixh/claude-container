# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a Docker container setup for running Claude Code, designed to also function as a VS Code dev container.

## Build Commands

```bash
# Build the Docker image
docker build -t claude-container .

# Run the container
docker run -it claude-container

# Build and run with docker-compose (when available)
docker-compose up --build
```

## Dev Container Usage

Open this repository in VS Code and use "Dev Containers: Reopen in Container" from the command palette, or use the devcontainer CLI:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

## Architecture

- `Dockerfile` - Main container definition for Claude Code environment
- `.devcontainer/` - VS Code dev container configuration
  - `devcontainer.json` - Dev container settings and extensions
- `docker-compose.yml` - Multi-container orchestration (if needed)
