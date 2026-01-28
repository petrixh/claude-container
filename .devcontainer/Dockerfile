# Claude Code Development Container
# Based on the official reference implementation with Java 21 support
# Multi-stage build supporting base and Docker-in-Docker variants

ARG NODE_VERSION=20
ARG VARIANT=base

# ========================================
# BASE-COMMON STAGE (shared dependencies)
# ========================================
FROM node:${NODE_VERSION}-bookworm as base-common

ARG TZ=Europe/Helsinki
ARG CLAUDE_CODE_VERSION=latest

ENV TZ=${TZ} \
    DEBIAN_FRONTEND=noninteractive \
    CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION} \
    NODE_PATH=/usr/local/lib/node_modules \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

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
    vim \
    wget \
    zsh \
    # Firewall tools
    iptables \
    dnsutils \
    iputils-ping \
    apt-transport-https \
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

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Install Playwright globally with Chromium headless shell (for arm64/amd64)
RUN npm install -g playwright \
    && mkdir -p /opt/playwright-browsers \
    && npx playwright install --with-deps --only-shell chromium \
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
    && echo '\n# History settings for persistent history' >> /home/node/.zshrc \
    && echo 'HISTFILE=/commandhistory/.zsh_history' >> /home/node/.zshrc \
    && echo 'HISTSIZE=10000' >> /home/node/.zshrc \
    && echo 'SAVEHIST=10000' >> /home/node/.zshrc

# ========================================
# BASE STAGE (current container)
# ========================================
FROM base-common as base

USER root

# Copy firewall and entrypoint scripts
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Set working directory
WORKDIR /workspace

# Switch to node user
USER node

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]

# ========================================
# DIND STAGE (Docker-in-Docker)
# ========================================
FROM base-common as dind

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
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh \
             /usr/local/bin/entrypoint.sh \
             /usr/local/bin/entrypoint-dind.sh

WORKDIR /workspace
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/zsh"]
