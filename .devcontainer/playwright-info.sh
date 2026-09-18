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

    # Playwright Agent CLI
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" "$VERSION_FILE" | cut -d= -f2)
    CLI_CHROMIUM_BUILD=$(grep "^CLI_CHROMIUM_BUILD=" "$VERSION_FILE" | cut -d= -f2)
    if [ -n "$CLI_PKG_VER" ]; then
        echo ""
        echo "Agent CLI:           @playwright/cli@${CLI_PKG_VER}"
        echo "  Chromium:          ${CLI_CHROMIUM_BUILD:-unknown}"
        echo "  Skill:             ~/.claude/skills/playwright-cli"
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
echo "- Agent CLI (@playwright/cli): For agent browser automation —"
echo "    faster, lower token use. Pre-installed skill: ~/.claude/skills/playwright-cli"
echo "    (run 'playwright-cli --help')"
