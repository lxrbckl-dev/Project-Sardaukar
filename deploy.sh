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
ORGS=$(grep 'name:' .claude/config/organizations.yml 2>/dev/null | sed 's/.*name: //' | tr '\n' ', ' | sed 's/,[ ]*$//')

INFO1="TPM (orchestrator)           ${TPM_COUNT} session"
INFO2="SWE (performance/Opus)       ${SWE_PERFORMANCE_CORES} cores"
INFO3="SWE (efficiency/Sonnet)      ${SWE_EFFICIENCY_CORES} core"
INFO4="QA  (gatekeeper)             ${QA_AGENT_COUNT} agent"
INFO5="Orgs: ${ORGS}"

# Print a padded line inside the box
sardaukar_line() {
    local text="$1"
    local vis=${#text} max=75
    if [ $vis -gt $max ]; then text="${text:0:$((max-3))}..."; vis=$max; fi
    printf -v pad '%*s' $((max - vis)) ''
    echo "│   ${text}${pad}│"
}

REPO_URL="github.com/lxrbckl-dev/Project-Sardaukar"

printf -v BORDER '%78s' ''; BORDER="${BORDER// /─}"
echo ""
echo "╭${BORDER}╮"
printf "│%78s│\n" ""
TITLE="Project Sardaukar v${VERSION}"
TITLE_PAD=$((75 - ${#TITLE} - ${#REPO_URL} - 1))
if [ $TITLE_PAD -lt 1 ]; then
    sardaukar_line "$TITLE"
else
    printf "│   %s%${TITLE_PAD}s%s │\n" "$TITLE" "" "$REPO_URL"
fi
printf "│%78s│\n" ""
echo "├${BORDER}┤"
printf "│%78s│\n" ""
sardaukar_line "$INFO1"
sardaukar_line "$INFO2"
sardaukar_line "$INFO3"
sardaukar_line "$INFO4"
printf "│%78s│\n" ""
sardaukar_line "$INFO5"
printf "│%78s│\n" ""
echo "╰${BORDER}╯"
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
