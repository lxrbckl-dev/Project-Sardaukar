#!/bin/bash
# Deploys the agent team — TPM as orchestrator with on-demand SWE/QA subagents.
# Pulls latest from git, then starts claude in the chosen mode.
#
# Usage:
#   ./deploy.sh                  → local CLI mode (interactive terminal)
#   ./deploy.sh --remote         → remote-control mode (connect via claude.ai/code)
#   ./deploy.sh --headless       → local CLI + headless Playwright
#   ./deploy.sh --remote --headless → remote-control + headless Playwright

set -e

# ── Agent Team Configuration ───────────────────────────────────────
# TPM — orchestrator (always 1, this is the session you're starting)
export TPM_COUNT=1                # There can only be one TPM

# SWE cores — like CPU cores, split between efficiency and performance
export SWE_AGENT_COUNT=3          # Total max concurrent SWE subagents
export SWE_EFFICIENCY_CORES=1     # Sonnet — routine tasks (dependency bumps, docs, simple fixes)
export SWE_PERFORMANCE_CORES=2    # Opus — complex tasks (refactors, breaking changes, hard debugging)

# QA — gatekeeper
export QA_AGENT_COUNT=1           # Max concurrent QA subagents (1 recommended to avoid merge conflicts)
# ───────────────────────────────────────────────────────────────────

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Pull latest changes (fast-forward only — won't auto-merge)
echo "[deploy] Pulling latest from git..."
git pull --ff-only || echo "[deploy] git pull failed or skipped — continuing with local version"

VERSION="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")"
SESSION_NAME="Sardaukar TPM v${VERSION}"

# Display team configuration
echo ""
ORGS=$(grep 'name:' .claude/config/organizations.yml 2>/dev/null | sed 's/.*name: //' | tr '\n' ', ' | sed 's/, $//')
echo "┌─────────────────────────────────────────────┐"
echo "│  Sardaukar Agent Team v${VERSION}                  │"
echo "├─────────────────────────────────────────────┤"
echo "│  TPM (orchestrator)       ${TPM_COUNT} session          │"
echo "│  SWE cores (total)        ${SWE_AGENT_COUNT} agents           │"
echo "│    ├─ Efficiency (Sonnet) ${SWE_EFFICIENCY_CORES} core             │"
echo "│    └─ Performance (Opus)  ${SWE_PERFORMANCE_CORES} cores            │"
echo "│  QA (gatekeeper)          ${QA_AGENT_COUNT} agent            │"
echo "├─────────────────────────────────────────────┤"
echo "│  Orgs: ${ORGS}"
echo "└─────────────────────────────────────────────┘"
echo ""

# Parse flags
REMOTE_MODE=false
HEADLESS_MODE=false
for arg in "$@"; do
    case "$arg" in
        --remote) REMOTE_MODE=true ;;
        --headless) HEADLESS_MODE=true ;;
    esac
done

# Set Playwright to headless if flagged
if [ "$HEADLESS_MODE" = true ]; then
    export PLAYWRIGHT_HEADLESS=1
    echo "[deploy] Playwright: headless mode (no browser window)"
fi

if [ "$REMOTE_MODE" = true ]; then
    echo "[deploy] Starting $SESSION_NAME in remote-control mode..."
    echo "[deploy] Connect from your phone at https://claude.ai/code"
    exec claude remote-control --permission-mode bypassPermissions --name "$SESSION_NAME"
else
    echo "[deploy] Starting $SESSION_NAME in local CLI mode..."
    exec claude --dangerously-skip-permissions
fi
