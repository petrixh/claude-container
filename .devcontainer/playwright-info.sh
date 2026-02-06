#!/bin/bash
# Display Playwright version and compatibility information

VERSION_FILE="/opt/playwright-browsers/VERSION"

echo "=== Playwright Browser Info ==="
echo ""

if [ -f "$VERSION_FILE" ]; then
    grep -v "^#" "$VERSION_FILE" | grep -v "^$"
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
