#!/bin/sh
# Writes a sweep trigger to the webhook queue for TPM to pick up.
# Run by the cron container on a schedule (default: every 30 minutes).

QUEUE_DIR="${QUEUE_DIR:-/data/queue/incoming}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%S")

ENVELOPE=$(cat <<EOF
{
  "org": "system",
  "event": "sweep",
  "delivery_id": "cron-${TIMESTAMP}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "payload": {
    "action": "sweep",
    "trigger": "cron"
  }
}
EOF
)

FILENAME="${TIMESTAMP}_system_sweep_trigger.json"
# Write to temp file then rename for atomicity — prevents TPM from reading partial JSON
echo "$ENVELOPE" > "${QUEUE_DIR}/${FILENAME}.tmp"
mv "${QUEUE_DIR}/${FILENAME}.tmp" "${QUEUE_DIR}/${FILENAME}"
echo "[cron] Sweep trigger written: ${FILENAME}"
