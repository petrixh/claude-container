# Coding Agent Development Container
# Based on the official reference implementation with Java 21 support
# Multi-stage build supporting base (Claude Code), opencode, and Docker-in-Docker variants

ARG NODE_VERSION=20
ARG VARIANT=base

# ========================================
# BASE-COMMON STAGE (shared dependencies)
# Agent-agnostic: tools, Java, Playwright, browsers.
# Agent CLIs (Claude Code, OpenCode) are added in downstream stages.
# ========================================
FROM node:${NODE_VERSION}-bookworm AS base-common

ARG TZ=Europe/Helsinki

ENV TZ=${TZ} \
    DEBIAN_FRONTEND=noninteractive \
    NODE_PATH=/usr/local/lib/node_modules \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    less \
    lsb-release \
    openssh-client \
    sudo \
    nano \
    vim \
    wget \
    zsh \
    screen \
    htop \
    # Firewall tools
    iptables \
    dnsutils \
    iputils-ping \
    apt-transport-https \
    # Process tools (ps aux needed by CDP proxy monitor)
    procps \
    # Port forwarding for Playwright CDP (headless shell only binds to localhost)
    socat \
    # Playwright browser dependencies (for Java Playwright)
    libxcursor1 \
    libgtk-3-0 \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Java 21 (Eclipse Temurin/Adoptium)
RUN mkdir -p /etc/apt/keyrings \
    && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y temurin-21-jdk \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME (create symlink for architecture independence)
RUN ln -s /usr/lib/jvm/temurin-21-jdk-* /usr/lib/jvm/temurin-21-jdk
ENV JAVA_HOME=/usr/lib/jvm/temurin-21-jdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Install Playwright globally with Chromium browser (full + headless shell)
# Pre-install browsers so they're included in the image and don't need to be downloaded at runtime
# Create VERSION file documenting compatibility for Java Playwright users
RUN npm install -g playwright \
    && mkdir -p /opt/playwright-browsers \
    && PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers npx playwright install --with-deps chromium \
    && PLAYWRIGHT_VERSION=$(npx playwright --version | sed 's/Version //') \
    && echo "# Playwright Browser Compatibility Info" > /opt/playwright-browsers/VERSION \
    && echo "# Generated at build time - do not edit" >> /opt/playwright-browsers/VERSION \
    && echo "" >> /opt/playwright-browsers/VERSION \
    && echo "PLAYWRIGHT_VERSION=${PLAYWRIGHT_VERSION}" >> /opt/playwright-browsers/VERSION \
    && echo "CHROMIUM_BUILD=$(ls -d /opt/playwright-browsers/chromium-* | head -1 | xargs basename)" >> /opt/playwright-browsers/VERSION \
    && echo "" >> /opt/playwright-browsers/VERSION \
    && echo "# Java Playwright Compatibility:" >> /opt/playwright-browsers/VERSION \
    && echo "# Use com.microsoft.playwright version matching PLAYWRIGHT_VERSION above" >> /opt/playwright-browsers/VERSION \
    && echo "# Example Maven dependency:" >> /opt/playwright-browsers/VERSION \
    && echo "#   <artifactId>playwright</artifactId>" >> /opt/playwright-browsers/VERSION \
    && echo "#   <version>${PLAYWRIGHT_VERSION}</version>" >> /opt/playwright-browsers/VERSION

# Install Playwright MCP and its required browsers (newer version than standard Playwright)
# This ensures Claude's MCP tools work without downloading browsers at runtime
# The MCP typically requires a newer Playwright version with a different chromium build
RUN npm install -g @playwright/mcp \
    && MCP_PACKAGE_VERSION=$(npm list -g @playwright/mcp --json 2>/dev/null | jq -r '.dependencies["@playwright/mcp"].version // empty') \
    && MCP_PW_VERSION=$(npm view @playwright/mcp dependencies.playwright 2>/dev/null || echo "") \
    && if [ -n "$MCP_PW_VERSION" ]; then \
         echo "Installing MCP Playwright browsers (version ${MCP_PW_VERSION})..." \
         && PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers npx playwright@${MCP_PW_VERSION} install --with-deps chromium \
         && echo "" >> /opt/playwright-browsers/VERSION \
         && echo "# MCP Playwright (for Claude's browser tools):" >> /opt/playwright-browsers/VERSION \
         && echo "MCP_PACKAGE_VERSION=${MCP_PACKAGE_VERSION}" >> /opt/playwright-browsers/VERSION \
         && echo "MCP_PLAYWRIGHT_VERSION=${MCP_PW_VERSION}" >> /opt/playwright-browsers/VERSION \
         && echo "MCP_CHROMIUM_BUILD=$(ls -d /opt/playwright-browsers/chromium-* | tail -1 | xargs basename)" >> /opt/playwright-browsers/VERSION; \
       else \
         echo "Warning: Could not determine MCP Playwright version, skipping MCP browser install"; \
       fi

# Make npm global directories and Playwright browsers writable by node user
# This allows Claude to self-update and Java Playwright to create lock files
RUN chown -R node:node /usr/local/lib/node_modules \
    && chown -R node:node /usr/local/bin \
    && chown -R node:node /opt/playwright-browsers \
    && chmod -R 755 /opt/playwright-browsers

# Configure node user with sudo access
RUN echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# Create directories for the node user
RUN mkdir -p /home/node/.claude /home/node/.config/gh /commandhistory \
    && chown -R node:node /home/node /commandhistory

# Install Oh My Zsh for the node user
USER node
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Configure zsh with useful aliases
RUN echo '\n# Claude Code aliases' >> /home/node/.zshrc \
    && echo 'alias firewall-reload="sudo /usr/local/bin/init-firewall.sh"' >> /home/node/.zshrc \
    && echo 'alias firewall-status="sudo iptables -L -n -v"' >> /home/node/.zshrc \
    && echo 'alias playwright-info="playwright-info"' >> /home/node/.zshrc \
    && echo '\n# History settings for persistent history' >> /home/node/.zshrc \
    && echo 'HISTFILE=/commandhistory/.zsh_history' >> /home/node/.zshrc \
    && echo 'HISTSIZE=10000' >> /home/node/.zshrc \
    && echo 'SAVEHIST=10000' >> /home/node/.zshrc

# ========================================
# BASE STAGE (Claude Code)
# ========================================
FROM base-common AS base

# CLAUDE_CODE_VERSION: pass "latest" (default), "stable", or a specific
# version like "2.1.126". The installer always downloads the newest binary
# and uses this value to set the active launcher target.
ARG CLAUDE_CODE_VERSION=latest
ENV CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION}

USER root

# Install Claude Code via the official bash installer.
# Runs as `node` so the binary lands in /home/node/.local/share/claude/...
# with a symlink at /home/node/.local/bin/claude. We add a second symlink
# in /usr/local/bin so the CLI is on PATH for any user.
RUN if [ "${CLAUDE_CODE_VERSION}" = "latest" ]; then \
      su - node -c "curl -fsSL https://claude.ai/install.sh | bash"; \
    else \
      su - node -c "curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}"; \
    fi \
    && ln -sf /home/node/.local/bin/claude /usr/local/bin/claude

# Copy firewall, entrypoint, and helper scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY playwright-info.sh /usr/local/bin/playwright-info
COPY cdp-proxy-monitor.sh /usr/local/bin/cdp-proxy-monitor
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh /usr/local/bin/playwright-info /usr/local/bin/cdp-proxy-monitor

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace

# Switch to node user
USER node

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]

# ========================================
# OPENCODE STAGE (sst/opencode)
# ========================================
FROM base-common AS opencode

# OPENCODE_VERSION: pass "latest" (default) or a specific version like "1.14.33"
ARG OPENCODE_VERSION=latest
ENV OPENCODE_VERSION=${OPENCODE_VERSION}

USER root

# Install OpenCode via the official bash installer.
# Runs as `node` so the binary lands in /home/node/.opencode/bin/opencode,
# then symlinked into /usr/local/bin for system-wide PATH availability.
# Tar is already provided by the node:bookworm base image.
RUN if [ "${OPENCODE_VERSION}" = "latest" ]; then \
      su - node -c "curl -fsSL https://opencode.ai/install | bash"; \
    else \
      su - node -c "curl -fsSL https://opencode.ai/install | bash -s -- --version ${OPENCODE_VERSION}"; \
    fi \
    && ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode

# Copy firewall, entrypoint, and helper scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint-opencode.sh /usr/local/bin/entrypoint.sh
COPY playwright-info.sh /usr/local/bin/playwright-info
COPY cdp-proxy-monitor.sh /usr/local/bin/cdp-proxy-monitor
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh /usr/local/bin/playwright-info /usr/local/bin/cdp-proxy-monitor

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace

# Switch to node user
USER node

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]

# ========================================
# DIND STAGE (Claude Code + Docker-in-Docker)
# ========================================
FROM base AS dind

USER root

# Install Docker CE
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | \
       gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | \
       tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Configure Docker daemon
RUN mkdir -p /etc/docker && cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "features": {
    "buildkit": true
  }
}
EOF

# Add node user to docker group
RUN usermod -aG docker node

# Create Docker data directory
RUN mkdir -p /var/lib/docker /var/log && chmod 755 /var/lib/docker

# Copy scripts (including new DinD entrypoint)
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY entrypoint-dind.sh /usr/local/bin/entrypoint-dind.sh
COPY playwright-info.sh /usr/local/bin/playwright-info
COPY cdp-proxy-monitor.sh /usr/local/bin/cdp-proxy-monitor
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh \
             /usr/local/bin/entrypoint.sh \
             /usr/local/bin/entrypoint-dind.sh \
             /usr/local/bin/playwright-info \
             /usr/local/bin/cdp-proxy-monitor

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/zsh"]
