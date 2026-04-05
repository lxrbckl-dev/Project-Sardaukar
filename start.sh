#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/docker"
ENV_FILE="${DOCKER_DIR}/.env"

# Check for .env file
if [ ! -f "$ENV_FILE" ]; then
    echo "[start] No .env file found. Copying from .env.example..."
    cp "${DOCKER_DIR}/.env.example" "$ENV_FILE"
    echo "[start] Please edit ${ENV_FILE} with your actual secrets, then run this script again."
    exit 1
fi

# Check for unmodified placeholder secrets
if grep -q 'CHANGE_ME' "$ENV_FILE"; then
    echo "[start] ERROR: .env still contains CHANGE_ME placeholder values."
    echo "[start] Generate real secrets with: openssl rand -hex 32"
    echo "[start] Edit ${ENV_FILE} and replace all CHANGE_ME values before starting."
    exit 1
fi

echo "[start] Starting Project Sardaukar"

# Create required directories with open permissions so container users can write
mkdir -p "${SCRIPT_DIR}/queue/incoming" "${SCRIPT_DIR}/queue/processing" "${SCRIPT_DIR}/queue/done" "${SCRIPT_DIR}/queue/failed"
mkdir -p "${SCRIPT_DIR}/sessions"
mkdir -p "${SCRIPT_DIR}/logs"
chmod -R 777 "${SCRIPT_DIR}/queue" "${SCRIPT_DIR}/sessions" "${SCRIPT_DIR}/logs"

# Start all services
cd "$DOCKER_DIR"
docker compose --env-file .env up -d --build

echo "[start] All containers started."
echo "[start] Dashboard:        http://localhost:3801"
echo "[start] Webhook listener: http://localhost:3800/health"
echo "[start] Ctrl monitoring:  http://localhost:3802"
echo "[start] TPM agent is the orchestrator — it spawns SWE/QA subagents on demand."
