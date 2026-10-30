#!/bin/bash
# Entrypoint for Docker-in-Docker variant
# The Docker daemon is started by container-init (run from the standard entrypoint,
# before the firewall), unless DIND_ENABLED=0.

set -e

# Run standard entrypoint (includes Docker daemon, firewall and sudo policy setup)
exec /usr/local/sbin/entrypoint.sh "$@"
