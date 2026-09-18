#!/bin/bash
# Entrypoint script for Claude Code container
# Initializes firewall and executes the provided command

set -e

# Ensure CLAUDE_CONFIG_DIR is set so claude CLI writes config to the correct
# directory (the one that gets bind-mounted / volume-mounted for persistence)
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-/home/node/.claude}"

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
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    CLI_CHROMIUM_BUILD=$(grep "^CLI_CHROMIUM_BUILD=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    echo "  Playwright:   ${PW_VER} (${CHROMIUM_BUILD})"
    if [[ -n "${CLI_PKG_VER}" ]]; then
        echo "  Agent CLI:    @playwright/cli@${CLI_PKG_VER} (${CLI_CHROMIUM_BUILD})"
    fi
    echo "  Browsers:     ${PLAYWRIGHT_BROWSERS_PATH:-/opt/playwright-browsers}"
fi

# Show Java version
if command -v java &> /dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
    echo "  Java:         ${JAVA_VER}"
fi

echo "========================================"

# Show browser-automation hint for the Playwright Agent CLI.
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${CLI_PKG_VER}" ]]; then
        echo ""
        echo "Playwright Agent CLI (browser automation — faster, lower token use):"
        echo "  Skill pre-installed at ~/.claude/skills/playwright-cli — Claude loads it on demand."
        echo "  Drive a browser directly, e.g.: playwright-cli open && playwright-cli goto https://example.com"
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
      },
      {
        "matcher": "elicitation_dialog",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -d \"Claude is waiting for your answer\" ${NOTIFICATION_URL}"
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

# Configure default MCP servers using claude mcp add-json (user scope)
# Only adds if not already configured (avoids overwriting user customizations)
add_mcp_if_missing() {
    local name="$1"
    local json="$2"
    if claude mcp get "${name}" > /dev/null 2>&1; then
        echo "  MCP '${name}' already configured, skipping"
    else
        claude mcp add-json --scope user "${name}" "${json}" 2>/dev/null && \
            echo "  MCP '${name}' added" || \
            echo "  Warning: Failed to add MCP '${name}'"
    fi
}

echo "Configuring default MCP servers..."
# Browser automation is not an MCP here: the Playwright MCP was removed in
# favour of the Playwright Agent CLI (see #27), which the image installs
# together with its skill.
add_mcp_if_missing "Vaadin" '{"type":"http","url":"https://mcp.vaadin.com/docs"}'

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

# Show Chrome DevTools remote debugging hint.
# Copy-paste instruction the user can hand to their coding agent (Claude/OpenCode)
# so it launches a browser you can attach DevTools to from your host.
echo "Chrome DevTools (CDP) remote debugging:"
echo "  Copy the block below and give it to your agent ----------------------------"
echo "  Launch the browser with CDP on a FIXED port. Two flags are mandatory:"
echo "    --remote-debugging-port=9222   (Playwright defaults to --remote-debugging-pipe,"
echo "                                    which exposes NO TCP port)"
echo "    --remote-allow-origins=*       (Chrome 111+ returns HTTP 403 on the DevTools"
echo "                                    WebSocket without it)"
echo "  Loopback bind is enough — no socat / 0.0.0.0 bridge: the port-forward rewrites the host."
echo "  - Playwright Agent CLI: put the flags in the config's browser.launchOptions.args, then"
echo "      playwright-cli open --config=<file>"
echo "  - Raw Playwright: chromium.launch({ args: ['--remote-debugging-port=9222','--remote-allow-origins=*'] })"
echo "  ---------------------------------------------------------------------------"
echo "  Then forward port 9222 to your machine and open chrome://inspect."
echo ""

# Execute the passed command (or default to zsh)
exec "$@"
