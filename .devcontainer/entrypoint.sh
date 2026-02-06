#!/bin/bash
# Entrypoint script for Claude Code container
# Initializes firewall and executes the provided command

set -e

# Display welcome message with version info
echo "========================================"
echo "  Claude Code Container"
echo "========================================"

# Show Claude version
if command -v claude &> /dev/null; then
    CLAUDE_VER=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    echo "  Claude Code:  ${CLAUDE_VER}"
fi

# Show Playwright version from VERSION file
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    PW_VER=$(grep "^PLAYWRIGHT_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    CHROMIUM_BUILD=$(grep "^CHROMIUM_BUILD=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    echo "  Playwright:   ${PW_VER} (${CHROMIUM_BUILD})"
    echo "  Browsers:     ${PLAYWRIGHT_BROWSERS_PATH:-/opt/playwright-browsers}"
fi

# Show Java version
if command -v java &> /dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "  Java:         ${JAVA_VER}"
fi

echo "========================================"
echo ""

# Initialize firewall if we have the capability (unless SKIP_FIREWALL is set)
# This requires NET_ADMIN capability to be set
if [[ "${SKIP_FIREWALL:-0}" == "1" ]]; then
    echo "SKIP_FIREWALL=1 detected, skipping firewall initialization."
    echo ""
elif command -v iptables &> /dev/null; then
    echo "Initializing firewall..."
    if sudo /usr/local/bin/init-firewall.sh; then
        echo "Firewall initialized successfully."
    else
        echo "Warning: Firewall initialization failed. Continuing without firewall."
    fi
    echo ""
fi

# Set up Playwright CDP port forwarding if enabled
# The headless shell only binds to localhost, so we use socat to expose it externally
if [[ -n "${PLAYWRIGHT_CHROMIUM_DEBUG_PORT}" ]]; then
    # External port (0.0.0.0) is PLAYWRIGHT_CHROMIUM_DEBUG_PORT
    # Internal port (127.0.0.1) is PLAYWRIGHT_CHROMIUM_DEBUG_PORT + 1
    export PLAYWRIGHT_CDP_INTERNAL_PORT=$((PLAYWRIGHT_CHROMIUM_DEBUG_PORT + 1))

    echo "Playwright CDP debugging enabled:"
    echo "  External port: 0.0.0.0:${PLAYWRIGHT_CHROMIUM_DEBUG_PORT}"
    echo "  Internal port: 127.0.0.1:${PLAYWRIGHT_CDP_INTERNAL_PORT}"
    echo ""
    echo "Launch Playwright with: --remote-debugging-port=${PLAYWRIGHT_CDP_INTERNAL_PORT}"
    echo "Or use: chromium.launch({ args: ['--remote-debugging-port=${PLAYWRIGHT_CDP_INTERNAL_PORT}'] })"
    echo ""

    # Start socat forwarder in background
    socat TCP-LISTEN:${PLAYWRIGHT_CHROMIUM_DEBUG_PORT},fork,reuseaddr,bind=0.0.0.0 \
          TCP:127.0.0.1:${PLAYWRIGHT_CDP_INTERNAL_PORT} &
    echo "CDP port forwarder started (socat PID: $!)"
    echo ""
fi

# Execute the passed command (or default to zsh)
exec "$@"
