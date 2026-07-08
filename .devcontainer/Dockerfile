# Coding Agent Development Container
# Based on the official reference implementation with Java 21 support
# Multi-stage build supporting base (Claude Code), opencode, and their
# Docker-in-Docker variants (dind, opencode-dind)

ARG NODE_VERSION=22
ARG VARIANT=base

# ========================================
# BASE-COMMON STAGE (shared dependencies)
# Agent-agnostic: tools, Java, Playwright, browsers.
# Agent CLIs (Claude Code, OpenCode) are added in downstream stages.
# ========================================
FROM node:${NODE_VERSION}-trixie AS base-common

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

# Install the Playwright Agent CLI (@playwright/cli) and its required browser.
# Coding agents drive the browser with `playwright-cli` shell commands and concise
# output (no tool schemas / page snapshots held in context), which is fast and
# token-efficient. It bundles its own, newer playwright-core, so it needs its own
# chromium build pre-installed here to avoid a runtime download (which the firewall
# would block). The agent-facing skill is installed further down, once the node
# user's home directory exists.
RUN npm install -g @playwright/cli \
    && CLI_PACKAGE_VERSION=$(npm list -g @playwright/cli --json 2>/dev/null | jq -r '.dependencies["@playwright/cli"].version // empty') \
    && PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers playwright-cli install-browser chromium --with-deps \
    && echo "" >> /opt/playwright-browsers/VERSION \
    && echo "# Playwright Agent CLI (for agent browser automation via shell commands):" >> /opt/playwright-browsers/VERSION \
    && echo "CLI_PACKAGE_VERSION=${CLI_PACKAGE_VERSION}" >> /opt/playwright-browsers/VERSION \
    && echo "CLI_CHROMIUM_BUILD=$(ls -dt /opt/playwright-browsers/chromium-* | head -1 | xargs basename)" >> /opt/playwright-browsers/VERSION

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

# Install the Playwright Agent CLI skill into the node user's personal skills
# directory. `playwright-cli install --skills claude` writes to ~/.claude/skills.
# Claude Code reads ~/.claude/skills, and OpenCode also discovers skills there
# (in addition to ~/.config/opencode/skills), so this single copy serves the
# base, opencode and dind variants alike. Baking it into the image keeps it out
# of the user's mounted workspace (no repo pollution) and available everywhere.
RUN su - node -c "playwright-cli install --skills claude"

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
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh /usr/local/bin/playwright-info

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
# Tar is already provided by the node:trixie base image.
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
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh /usr/local/bin/playwright-info

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

# Install Docker CE and configure the daemon (shared with opencode-dind).
COPY install-docker.sh /usr/local/bin/install-docker.sh
RUN chmod +x /usr/local/bin/install-docker.sh && /usr/local/bin/install-docker.sh

# Add node user to docker group
RUN usermod -aG docker node

# Copy scripts (including the DinD entrypoint)
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY entrypoint-dind.sh /usr/local/bin/entrypoint-dind.sh
COPY playwright-info.sh /usr/local/bin/playwright-info
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh \
             /usr/local/bin/entrypoint.sh \
             /usr/local/bin/entrypoint-dind.sh \
             /usr/local/bin/playwright-info

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/zsh"]

# ========================================
# OPENCODE-DIND STAGE (OpenCode + Docker-in-Docker)
# ========================================
# Same Docker-in-Docker setup as the `dind` stage, but on top of the OpenCode
# agent instead of Claude Code. The DinD entrypoint is agent-agnostic: it starts
# dockerd, then execs /usr/local/bin/entrypoint.sh — which the opencode stage
# already installed as the OpenCode entrypoint.
FROM opencode AS opencode-dind

USER root

# Install Docker CE and configure the daemon (shared with dind).
COPY install-docker.sh /usr/local/bin/install-docker.sh
RUN chmod +x /usr/local/bin/install-docker.sh && /usr/local/bin/install-docker.sh

# Add node user to docker group
RUN usermod -aG docker node

# Copy the DinD entrypoint (other scripts were installed by the opencode stage,
# whose entrypoint-opencode.sh already lives at /usr/local/bin/entrypoint.sh).
COPY entrypoint-dind.sh /usr/local/bin/entrypoint-dind.sh
RUN chmod +x /usr/local/bin/entrypoint-dind.sh

WORKDIR /workspace
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/zsh"]
