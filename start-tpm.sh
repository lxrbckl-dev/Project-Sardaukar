#!/bin/bash
# Wrapper that starts TPM with a version-tagged session name.
# Reads VERSION from the project root and passes it to claude remote-control.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")"
SESSION_NAME="Sardaukar TPM v${VERSION}"

cd "$PROJECT_DIR"
exec claude remote-control --permission-mode bypassPermissions --name "$SESSION_NAME"
