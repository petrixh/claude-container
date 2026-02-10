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
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    MCP_PW_VER=$(grep "^MCP_PLAYWRIGHT_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    MCP_CHROMIUM_BUILD=$(grep "^MCP_CHROMIUM_BUILD=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    echo "  Playwright:   ${PW_VER} (${CHROMIUM_BUILD})"
    if [[ -n "${MCP_PW_VER}" ]]; then
        echo "  MCP:          @playwright/mcp@${MCP_PKG_VER} (${MCP_CHROMIUM_BUILD})"
    fi
    echo "  Browsers:     ${PLAYWRIGHT_BROWSERS_PATH:-/opt/playwright-browsers}"
fi

# Show Java version
if command -v java &> /dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "  Java:         ${JAVA_VER}"
fi

echo "========================================"

# Show MCP configuration hint if MCP is installed
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${MCP_PKG_VER}" ]]; then
        echo ""
        echo "Playwright MCP .mcp.json (use pre-installed browsers):"
        echo '  "playwright": {'
        echo '    "command": "npx",'
        echo '    "args": ['
        echo "      \"@playwright/mcp@${MCP_PKG_VER}\","
        echo '      "--headless",'
        echo '      "--browser",'
        echo '      "chromium"'
        echo '    ]'
        echo '  }'
    fi
fi
echo ""

# Configure git identity if env vars are provided
if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --global user.name "${GIT_USER_NAME}"
    echo "Git user.name configured: ${GIT_USER_NAME}"
fi
if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
    git config --global user.email "${GIT_USER_EMAIL}"
    echo "Git user.email configured: ${GIT_USER_EMAIL}"
fi

# Set up Vaadin Pro Key file if env var is provided
if [[ -n "${VAADIN_PRO_KEY:-}" ]]; then
    mkdir -p /home/node/.vaadin
    echo "${VAADIN_PRO_KEY}" > /home/node/.vaadin/proKey
    echo "Vaadin Pro key configured (~/.vaadin/proKey)"
fi

# Configure Claude Code notification hooks if NOTIFICATION_URL is provided
if [[ -n "${NOTIFICATION_URL:-}" ]]; then
    CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-/home/node/.claude}/settings.json"
    mkdir -p "$(dirname "${CLAUDE_SETTINGS}")"

    # Build the hooks JSON
    # Enabled: idle_prompt (Claude waiting for input), permission_prompt (needs permission)
    # Additional matchers available: elicitation_dialog, auth_success
    # Additional hook events: Stop (every response), TaskCompleted
    HOOKS_JSON=$(cat <<HOOKEOF
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -d \"Claude is idle - waiting for input\" ${NOTIFICATION_URL}"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -d \"Claude needs permission to proceed\" ${NOTIFICATION_URL}"
          }
        ]
      }
    ]
  }
}
HOOKEOF
    )

    # Merge hooks into existing settings.json (or create new one)
    if [[ -f "${CLAUDE_SETTINGS}" ]]; then
        MERGED=$(jq -s '.[0] * .[1]' "${CLAUDE_SETTINGS}" <(echo "${HOOKS_JSON}"))
        echo "${MERGED}" > "${CLAUDE_SETTINGS}"
    else
        echo "${HOOKS_JSON}" > "${CLAUDE_SETTINGS}"
    fi
    echo "Notification hooks configured for: ${NOTIFICATION_URL}"
fi

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
