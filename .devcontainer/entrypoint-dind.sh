#!/bin/bash
# Entrypoint for Docker-in-Docker variant
# Starts dockerd and then runs standard entrypoint

set -e

# Create log file with proper permissions
sudo touch /var/log/docker.log
sudo chmod 666 /var/log/docker.log

# Start Docker daemon in background if not already running
if ! pgrep dockerd > /dev/null; then
    echo "Starting Docker daemon..."

    # Start dockerd as root in background
    sudo dockerd > /var/log/docker.log 2>&1 &

    # Wait for Docker to be ready (max 30 seconds)
    echo "Waiting for Docker daemon..."
    timeout=30
    while ! docker info > /dev/null 2>&1; do
        sleep 1
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            echo "Error: Docker daemon failed to start"
            cat /var/log/docker.log
            exit 1
        fi
    done

    echo "Docker daemon ready."
    echo ""
fi

# Run standard entrypoint (includes firewall init)
exec /usr/local/bin/entrypoint.sh "$@"
