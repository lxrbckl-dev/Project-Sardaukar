#!/bin/bash
# Generates LaunchAgent plist file from template with your local paths,
# installs it, and starts the service.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
CLAUDE_PATH="$(which claude)"
NODE_BIN_DIR="$(dirname "$CLAUDE_PATH")"

if [ -z "$CLAUDE_PATH" ]; then
    echo "Error: claude not found in PATH. Install Claude Code CLI first."
    exit 1
fi

echo "Generating LaunchAgent plist..."
echo "  PROJECT_DIR:  $PROJECT_DIR"
echo "  HOME_DIR:     $HOME_DIR"
echo "  CLAUDE_PATH:  $CLAUDE_PATH"
echo "  NODE_BIN_DIR: $NODE_BIN_DIR"

mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/launchagents"

# Generate TPM plist
sed \
    -e "s|__CLAUDE_PATH__|$CLAUDE_PATH|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__NODE_BIN_DIR__|$NODE_BIN_DIR|g" \
    -e "s|__HOME_DIR__|$HOME_DIR|g" \
    "$PROJECT_DIR/launchagents/com.sardaukar.tpm.plist.example" \
    > "$PROJECT_DIR/launchagents/com.sardaukar.tpm.plist"

echo "Generated plist file."

# Unload existing (ignore errors if not loaded)
launchctl unload ~/Library/LaunchAgents/com.sardaukar.tpm.plist 2>/dev/null || true

# Symlink into LaunchAgents
ln -sf "$PROJECT_DIR/launchagents/com.sardaukar.tpm.plist" ~/Library/LaunchAgents/

# Load (starts immediately)
launchctl load ~/Library/LaunchAgents/com.sardaukar.tpm.plist

echo ""
echo "LaunchAgent installed and started."
echo "  TPM log: $PROJECT_DIR/logs/tpm-launch.log"
echo ""
echo "To stop:"
echo "  launchctl unload ~/Library/LaunchAgents/com.sardaukar.tpm.plist"
