#!/bin/bash
# Install Docker CE (engine, CLI, containerd, buildx, compose plugin) and
# configure the daemon for the Docker-in-Docker variants.
#
# Shared by every DinD stage in the Dockerfile (Claude `dind`, OpenCode
# `opencode-dind`, ...) so the Docker setup lives in exactly one place. Run as
# root during the image build. Adding the `node` user to the `docker` group is
# left to the calling stage (it runs after this and is cheap/idempotent there).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Install Docker CE from Docker's official apt repository
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
rm -rf /var/lib/apt/lists/*

# Configure the Docker daemon
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
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

# Create Docker data directory
mkdir -p /var/lib/docker /var/log
chmod 755 /var/lib/docker
