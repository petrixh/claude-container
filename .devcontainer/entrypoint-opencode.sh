#!/bin/bash
# Entrypoint script for OpenCode container
# Initializes firewall and executes the provided command

set -e

# OpenCode's config/data/state/cache directories are symlinked to
# ${OPENCODE_PROJECT_DIR}/.opencode/* in the image (see the Dockerfile). Create the
# targets here rather than at build time: /workspace is a mount point, so anything
# written there during the build is shadowed once the bind mount lands.
# Non-fatal: a read-only or unwritable workspace should not stop the container from
# starting, it just means OpenCode has nowhere to keep state.
OPENCODE_PROJECT_DIR="${OPENCODE_PROJECT_DIR:-/workspace}"
OPENCODE_STATE_DIR="${OPENCODE_PROJECT_DIR}/.opencode"
if ! mkdir -p "${OPENCODE_STATE_DIR}"/{config,data,state,cache} 2> /dev/null; then
    echo "WARNING: could not create ${OPENCODE_STATE_DIR} - is ${OPENCODE_PROJECT_DIR} writable?"
    echo "         OpenCode will fail to start until it exists."
fi

# Display welcome message with version info
echo "========================================"
echo "  OpenCode Container"
echo "========================================"

# Show OpenCode version
if command -v opencode &> /dev/null; then
    OPENCODE_VER=$(opencode --version 2>/dev/null | head -1 || echo "unknown")
    echo "  OpenCode:     ${OPENCODE_VER}"
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

echo "  State:        ${OPENCODE_STATE_DIR}"
echo "========================================"

# Warn if the consolidated state folder is not ignored by git. It holds
# opencode.db, which stores provider credentials - committing it would publish
# them. Only the four runtime subdirectories need ignoring: .opencode also holds
# project config (opencode.json, agents/, commands/, skills/) that is meant to be
# committed, so a blanket .opencode/ rule would be wrong.
if command -v git &> /dev/null \
   && git -C "${OPENCODE_PROJECT_DIR}" rev-parse --is-inside-work-tree &> /dev/null \
   && ! git -C "${OPENCODE_PROJECT_DIR}" check-ignore -q .opencode/data 2> /dev/null; then
    echo ""
    echo "WARNING: ${OPENCODE_STATE_DIR}/data is not covered by .gitignore."
    echo "  It contains opencode.db, which stores your provider credentials."
    echo "  Add to .gitignore (keeping committable project config visible):"
    echo "    .opencode/config/"
    echo "    .opencode/data/"
    echo "    .opencode/state/"
    echo "    .opencode/cache/"
fi

# Show browser-automation hint for the Playwright Agent CLI.
if [[ -f /opt/playwright-browsers/VERSION ]]; then
    CLI_PKG_VER=$(grep "^CLI_PACKAGE_VERSION=" /opt/playwright-browsers/VERSION | cut -d= -f2)
    if [[ -n "${CLI_PKG_VER}" ]]; then
        echo ""
        echo "Playwright Agent CLI (browser automation — faster, lower token use):"
        echo "  Skill pre-installed at ~/.claude/skills/playwright-cli — OpenCode discovers it automatically."
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

# OpenCode V2 usage notes.
echo "OpenCode V2:"
echo "  Add a provider:   run 'opencode' and use /connect, or 'opencode auth login'"
echo "  Background server: 'opencode service status' (V2 shares one server per container)"
echo "  Scripted runs:     'opencode run --standalone ...' uses a private server instead"
echo "  Custom models need explicit limit + capabilities in opencode.json - the model"
echo "  catalog host (models.opencode.ai) is blocked by the firewall by default."
echo ""

# Execute the passed command (or default to zsh)
exec "$@"
