#!/bin/bash
set -eo pipefail

AGENT_TYPE="${AGENT_TYPE:-tpm}"
AGENT_DEFINITION="${AGENT_DEFINITION:-tpm-agent.md}"
SESSION_FILE_NAME="${SESSION_FILE_NAME:-${AGENT_TYPE}}"

# Clean up stale session URL from previous run so dashboard doesn't show an invalid link
rm -f "/data/sessions/${SESSION_FILE_NAME}-url.txt"

echo "[entrypoint] Starting ${AGENT_TYPE} agent with definition ${AGENT_DEFINITION}"
echo "[entrypoint] Session URL will be written to /data/sessions/${SESSION_FILE_NAME}-url.txt"

# Start claude with remote-control, capture all output.
# The --agent flag loads the agent definition which contains the Startup Sequence
# and Main Loop instructions. TPM will begin executing them automatically.
# If --prompt is not compatible with --remote-control, TPM still follows its agent
# definition. The user can also connect and issue commands at any time.
claude --remote-control --dangerously-skip-permissions --agent ".claude/agents/${AGENT_DEFINITION}" --prompt "You are now online. Execute your Startup Sequence, then enter your Main Loop." 2>&1 | tee "/data/sessions/${SESSION_FILE_NAME}-stdout.log" | while IFS= read -r line; do
    # Attempt to capture session URL from output
    # Match claude.ai URLs which are used for remote-control sessions
    # This regex may need updating if Claude changes its output format
    URL=$(echo "$line" | grep -oiE 'https?://(claude\.ai|app\.claude\.ai)[^ ]*' || true)
    if [ -n "$URL" ]; then
        echo "$URL" > "/data/sessions/${SESSION_FILE_NAME}-url.txt"
        echo "[entrypoint] Captured session URL: $URL" >&2
    fi
done
