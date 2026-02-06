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

# Show Chrome DevTools remote debugging hint
echo "Chrome DevTools (CDT) remote debugging:"
echo "  Auto-proxy that tracks Playwright's random debug port to 0.0.0.0:9222:"
echo "  nohup cdp-proxy-monitor > /tmp/cdp-proxy.log 2>&1 &"
echo "  Then forward port 9222 to your machine and open chrome://inspect"
echo ""

# Execute the passed command (or default to zsh)
exec "$@"
