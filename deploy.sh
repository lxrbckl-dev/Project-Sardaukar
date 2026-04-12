#!/bin/bash
# Deploys the agent team — TPM as orchestrator with on-demand SWE/QA subagents.
# Reads VERSION for the session name. Configure max concurrent SWEs below.

set -e

# Max concurrent SWE subagents TPM can spawn (default: 3)
export SWE_AGENT_COUNT=3

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")"
SESSION_NAME="Sardaukar TPM v${VERSION}"

cd "$PROJECT_DIR"
exec claude remote-control --permission-mode bypassPermissions --name "$SESSION_NAME"
