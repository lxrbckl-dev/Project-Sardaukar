#!/bin/bash
# Deploys the agent team — TPM as orchestrator with on-demand SWE/QA subagents.
# Pulls latest from git, then starts claude remote-control with a version-tagged session name.

set -e

# Max concurrent SWE subagents TPM can spawn (default: 3)
export SWE_AGENT_COUNT=3

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Pull latest changes (fast-forward only — won't auto-merge)
echo "[deploy] Pulling latest from git..."
git pull --ff-only || echo "[deploy] git pull failed or skipped — continuing with local version"

VERSION="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")"
SESSION_NAME="Sardaukar TPM v${VERSION}"

echo "[deploy] Starting $SESSION_NAME..."
exec claude remote-control --permission-mode bypassPermissions --name "$SESSION_NAME"
