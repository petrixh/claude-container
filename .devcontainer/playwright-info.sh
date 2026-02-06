#!/bin/bash
# Display Playwright version and compatibility information

VERSION_FILE="/opt/playwright-browsers/VERSION"

echo "=== Playwright Browser Info ==="
echo ""

if [ -f "$VERSION_FILE" ]; then
    # Standard Playwright
    PW_VER=$(grep "^PLAYWRIGHT_VERSION=" "$VERSION_FILE" | cut -d= -f2)
    CHROMIUM_BUILD=$(grep "^CHROMIUM_BUILD=" "$VERSION_FILE" | cut -d= -f2)
    echo "Standard Playwright: ${PW_VER:-unknown}"
    echo "  Chromium:          ${CHROMIUM_BUILD:-unknown}"

    # MCP Playwright
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" "$VERSION_FILE" | cut -d= -f2)
    MCP_PW_VER=$(grep "^MCP_PLAYWRIGHT_VERSION=" "$VERSION_FILE" | cut -d= -f2)
    MCP_CHROMIUM_BUILD=$(grep "^MCP_CHROMIUM_BUILD=" "$VERSION_FILE" | cut -d= -f2)
    if [ -n "$MCP_PW_VER" ]; then
        echo ""
        echo "MCP Package:         @playwright/mcp@${MCP_PKG_VER:-unknown}"
        echo "  Playwright:        ${MCP_PW_VER}"
        echo "  Chromium:          ${MCP_CHROMIUM_BUILD:-unknown}"
    fi
    echo ""
fi

echo "=== Installed Browsers ==="
ls -1 /opt/playwright-browsers/ | grep -v VERSION | grep -v "^\." | sort

echo ""
echo "=== Environment ==="
echo "PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH:-not set}"
echo "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-not set}"

echo ""
echo "=== Quick Check ==="
if command -v npx &> /dev/null; then
    echo "Node Playwright: $(npx playwright --version 2>/dev/null || echo 'not available')"
fi

echo ""
echo "=== Usage Notes ==="
echo "- Standard Playwright: For Java Playwright and direct Node.js usage"
echo "- MCP Playwright: For Claude's browser automation tools (@playwright/mcp)"

# Show recommended .mcp.json if MCP is installed
if [ -f "$VERSION_FILE" ]; then
    MCP_PKG_VER=$(grep "^MCP_PACKAGE_VERSION=" "$VERSION_FILE" | cut -d= -f2)
    if [ -n "$MCP_PKG_VER" ]; then
        echo ""
        echo "=== Recommended .mcp.json ==="
        echo "To use pre-installed browsers (no download at runtime):"
        echo ""
        echo '{'
        echo '  "mcpServers": {'
        echo '    "playwright": {'
        echo '      "command": "npx",'
        echo '      "args": ['
        echo "        \"@playwright/mcp@${MCP_PKG_VER}\","
        echo '        "--headless",'
        echo '        "--browser",'
        echo '        "chromium"'
        echo '      ]'
        echo '    }'
        echo '  }'
        echo '}'
    fi
fi
