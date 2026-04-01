#!/bin/bash

# --- Load Environment Variables ---
# Get the directory where this script is actually located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Load Environment Variables from the same folder as the script
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
else
    echo "Error: .env file not found in $SCRIPT_DIR"
    exit 1
fi


# --- Configuration ---
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/power_history.csv"
ERROR_LOG="$LOG_DIR/power_error.log"
LOCK_FILE="/tmp/power_alert.lock"
# Find the 'kasa' executable automatically
KASA_BIN=$(command -v kasa || echo "$HOME/.local/bin/kasa")

# Ensure log directory exists
mkdir -p "$LOG_DIR"

THRESHOLD=${1:-36}
COOLDOWN_MINUTES=30

# 1. Find IP via MAC (Variable loaded from .env)
# --- Smart IP Lookup ---
# 1. Try the last known IP from .env first
if [ -n "$LAST_IP" ] && [ "$LAST_IP" != "0.0.0.0" ] && ping -c 1 -W 1 "$LAST_IP" > /dev/null 2>&1; then
    PLUG_IP="$LAST_IP"
else
    # 2. Fallback: Run the heavy scan. Using absolute path for sudo and arp-scan
    # We also use 'stdbuf' to ensure we don't hit buffering issues in cron
    PLUG_IP=$(sudo /usr/sbin/arp-scan --localnet --quiet | grep -i "$PLUG_MAC" | awk '{print $1}')
    
    # 3. Safety Check: If arp-scan failed to find the MAC
    if [ -z "$PLUG_IP" ]; then
        echo "$(date): arp-scan could not find MAC $PLUG_MAC on the network." >> "$ERROR_LOG"
        exit 1
    fi

    # 4. Update the .env file if we found a new/different IP
    if [ "$PLUG_IP" != "$LAST_IP" ]; then
        sed -i "s/LAST_IP=.*/LAST_IP=\"$PLUG_IP\"/" "$SCRIPT_DIR/.env"
    fi
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
# Append the new data point first
echo "$(date '+%Y-%m-%d %H:%M:%S'),$WATTAGE" >> "$LOG_FILE"

# Define the clean header
HEADER="Timestamp,Wattage,Status"

# Grab the last 10,000 lines, but FILTER OUT any existing header lines
# 'grep -v' means "everything EXCEPT this word"
DATA=$(grep -v "Timestamp" "$LOG_FILE" | tail -n 10000)

# Overwrite the file with exactly one header and the cleaned data
echo -e "$HEADER\n$DATA" > "$LOG_FILE"
