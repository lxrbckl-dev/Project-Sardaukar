#!/bin/bash
# Deploys the agent team — TPM as orchestrator with on-demand SWE/QA subagents.
# Pulls latest from git, then starts claude in the chosen mode.
#
# Usage:
#   ./deploy.sh          → remote-control mode (connect via claude.ai/code)
#   ./deploy.sh --local  → interactive CLI mode (chat directly in terminal)

set -e

# Agent core allocation — like CPU cores
export SWE_AGENT_COUNT=3          # Total max concurrent SWE subagents
export SWE_EFFICIENCY_CORES=2     # Sonnet — routine tasks (dependency bumps, docs, simple fixes)
export SWE_PERFORMANCE_CORES=1    # Opus — complex tasks (refactors, breaking changes, hard debugging)

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Pull latest changes (fast-forward only — won't auto-merge)
echo "[deploy] Pulling latest from git..."
git pull --ff-only || echo "[deploy] git pull failed or skipped — continuing with local version"

VERSION="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")"
SESSION_NAME="Sardaukar TPM v${VERSION}"

if [ "$1" = "--local" ]; then
    echo "[deploy] Starting $SESSION_NAME in local CLI mode..."
    exec claude --dangerously-skip-permissions
else
    echo "[deploy] Starting $SESSION_NAME in remote-control mode..."
    echo "[deploy] Connect from your phone at https://claude.ai/code"
    exec claude remote-control --permission-mode bypassPermissions --name "$SESSION_NAME"
fi
