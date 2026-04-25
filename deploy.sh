#!/bin/bash
# Deploys the agent team — TPM as orchestrator with on-demand SWE/QA subagents.
# Pulls latest from git, then starts claude in the chosen mode.
#
# Usage:
#   ./deploy.sh                  → local CLI mode (interactive terminal)
#   ./deploy.sh --remote         → remote-control mode (connect via claude.ai/code)
#   ./deploy.sh --headless       → local CLI + headless Playwright
#   ./deploy.sh --skip-qa        → bypass QA; SWE self-merges agent PRs after green tests
#   ./deploy.sh --embedded       → HARDCORE focus on spawning repo: no tickets/board churn; every message presumed about spawning repo; local file edits only on current branch (you drive all git ops; PRs disabled; cross-repo out of scope)
#   ./deploy.sh --obsidian       → Obsidian vault mode (implies --embedded): agents follow vault conventions (YAML frontmatter, [[wikilinks]], #tags, callouts) on .md edits; no test gate (vaults have no tests); all embedded rules inherit
#   ./deploy.sh --remote --headless --skip-qa --embedded --obsidian → flags stack freely

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

SPAWNING_PWD="$PWD"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Pull latest changes (fast-forward only — won't auto-merge)
echo "[deploy] Pulling latest from git..."
git pull --ff-only || echo "[deploy] git pull failed or skipped — continuing with local version"

VERSION="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")"
SESSION_NAME="Sardaukar TPM v${VERSION}"

# Display team configuration
ORGS=$(grep 'name:' .claude/config/organizations.yml 2>/dev/null | sed 's/.*name: //' | tr '\n' ', ' | sed 's/,[ ]*$//')

# Parse flags early so the banner can reflect mode (e.g. QA disabled)
REMOTE_MODE=false
HEADLESS_MODE=false
SKIP_QA_MODE=false
EMBEDDED_MODE=false
OBSIDIAN_MODE=false
for arg in "$@"; do
    case "$arg" in
        --remote) REMOTE_MODE=true ;;
        --headless) HEADLESS_MODE=true ;;
        --skip-qa) SKIP_QA_MODE=true ;;
        --embedded) EMBEDDED_MODE=true ;;
        --obsidian) OBSIDIAN_MODE=true; EMBEDDED_MODE=true ;;
    esac
done

# Validate --embedded target before printing the banner — if the spawning
# directory is not a git repo, fail fast with a clear error.
if [ "$EMBEDDED_MODE" = true ] && ! git -C "$SPAWNING_PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[deploy] ERROR: --embedded requires a git repository."
    echo "[deploy] '$SPAWNING_PWD' is not a git working tree."
    echo "[deploy] Either cd into a git repo first, or deploy without --embedded."
    exit 1
fi

INFO1="TPM (orchestrator)           ${TPM_COUNT} session"
INFO2="SWE (performance/Opus)       ${SWE_PERFORMANCE_CORES} cores"
INFO3="SWE (efficiency/Sonnet)      ${SWE_EFFICIENCY_CORES} core"
if [ "$SKIP_QA_MODE" = true ]; then
    INFO4="QA  (gatekeeper)             disabled (--skip-qa)"
else
    INFO4="QA  (gatekeeper)             ${QA_AGENT_COUNT} agent"
fi
INFO5="Orgs: ${ORGS}"
if [ "$EMBEDDED_MODE" = true ]; then
    INFO6="Mode: embedded (spawning repo = $SPAWNING_PWD)"
fi
if [ "$OBSIDIAN_MODE" = true ]; then
    INFO7="Mode: obsidian (vault conventions active)"
fi

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
if [ "$EMBEDDED_MODE" = true ]; then
    printf "│%78s│\n" ""
    sardaukar_line "$INFO6"
fi
if [ "$OBSIDIAN_MODE" = true ]; then
    sardaukar_line "$INFO7"
fi
printf "│%78s│\n" ""
echo "╰${BORDER}╯"
echo ""

# Set Playwright to headless if flagged
if [ "$HEADLESS_MODE" = true ]; then
    export PLAYWRIGHT_HEADLESS=1
    echo "[deploy] Playwright: headless mode (no browser window)"
fi

# Export SKIP_QA if flagged — TPM reads this at startup to decide whether to spawn QA subagents
if [ "$SKIP_QA_MODE" = true ]; then
    export SKIP_QA=1
    echo "[deploy] QA bypass enabled — SWE will self-merge agent PRs"
fi

# Export SARDAUKAR_EMBEDDED if flagged — TPM reads this to set the default work target.
# Git-repo validation already happened before the banner printed; here we just export.
if [ "$EMBEDDED_MODE" = true ]; then
    export SARDAUKAR_EMBEDDED=1
    export SARDAUKAR_EMBEDDED_REPO="$SPAWNING_PWD"
    echo "[deploy] Embedded mode — working directly in spawning repo"
fi

# Export SARDAUKAR_OBSIDIAN if flagged — TPM reads this to apply Obsidian vault conventions.
# --obsidian implies --embedded (enforced above in the arg parser).
if [ "$OBSIDIAN_MODE" = true ]; then
    export SARDAUKAR_OBSIDIAN=1
    echo "[deploy] Obsidian mode — vault formatting conventions active; test gate disabled"
fi

if [ "$REMOTE_MODE" = true ]; then
    echo "[deploy] Starting $SESSION_NAME in remote-control mode..."
    echo "[deploy] Connect from your phone at https://claude.ai/code"
    exec claude remote-control --permission-mode bypassPermissions --name "$SESSION_NAME" "initialize"
else
    echo "[deploy] Starting $SESSION_NAME in local CLI mode..."
    exec claude --dangerously-skip-permissions "initialize"
fi
