#!/bin/bash

# --- Load Environment Variables ---
SCRIPT_DIR="/home/jon/projects/power_save"
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# --- Configuration ---
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/power_history.csv"
ERROR_LOG="$LOG_DIR/power_error.log"
LOCK_FILE="/tmp/power_alert.lock"
KASA_BIN="/home/jon/.local/bin/kasa"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

THRESHOLD=${1:-36}
COOLDOWN_MINUTES=30

# 1. Find IP via MAC (Variable loaded from .env)
PLUG_IP=$(sudo arp-scan --localnet --quiet | grep -i "$PLUG_MAC" | awk '{print $1}')

if [ -z "$PLUG_IP" ]; then
    echo "$(date): Could not find IP for MAC $PLUG_MAC" >> "$ERROR_LOG"
    exit 1
fi

# 2. Get Wattage
WATTAGE=$($KASA_BIN --host "$PLUG_IP" --discovery-timeout 1 --json energy | jq '.power_mw / 1000 | floor' 2>>"$ERROR_LOG")

if [ -z "$WATTAGE" ]; then
    echo "$(date): Could not reach plug at $PLUG_IP" >> "$ERROR_LOG"
    exit 1
fi

# 3. Cooldown Logic
if [ -f "$LOCK_FILE" ]; then
    LAST_ALERT=$(stat -c %Y "$LOCK_FILE")
    NOW=$(date +%s)
    DIFF=$(( (NOW - LAST_ALERT) / 60 ))
    if [ "$DIFF" -lt "$COOLDOWN_MINUTES" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$WATTAGE,COOLDOWN" >> "$LOG_FILE"
        exit 0
    fi
fi

# 4. Alerting (Variable loaded from .env)
if [ "$WATTAGE" -gt "$THRESHOLD" ]; then
    MESSAGE="⚠️ **Power Spike Detected** ⚠️\nDraw: **${WATTAGE}W** (Limit: ${THRESHOLD}W)"
    curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$MESSAGE\"}" "$WEBHOOK_URL"
    touch "$LOCK_FILE"
fi

# 5. Log & Cleanup
echo "$(date '+%Y-%m-%d %H:%M:%S'),$WATTAGE" >> "$LOG_FILE"
echo "$(tail -n 10000 "$LOG_FILE")" > "$LOG_FILE"
