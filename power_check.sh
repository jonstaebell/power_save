#!/bin/bash

# --- Load Environment Variables ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

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
KASA_BIN=$(command -v kasa || echo "$HOME/.local/bin/kasa")

mkdir -p "$LOG_DIR"

THRESHOLD=${1:-36}
COOLDOWN_MINUTES=30

# --- Smart IP Lookup & MAC Verification ---
# 1. Check if the LAST_IP actually matches our PLUG_MAC
# We use 'ip neighbor' which is faster and doesn't require sudo like arp-scan
CURRENT_MAC_AT_IP=$(ip neighbor show "$LAST_IP" | awk '{print $5}' | tr '[:upper:]' '[:lower:]')
EXPECTED_MAC=$(echo "$PLUG_MAC" | tr '[:upper:]' '[:lower:]')

if [ -n "$LAST_IP" ] && [ "$LAST_IP" != "0.0.0.0" ] && [ "$CURRENT_MAC_AT_IP" == "$EXPECTED_MAC" ]; then
    PLUG_IP="$LAST_IP"
else
    # 2. Fallback: The IP changed or the neighbor cache is stale. Run the scan.
    # We do a quick ping sweep or use arp-scan to refresh the table
    PLUG_IP=$(sudo /usr/sbin/arp-scan --localnet --quiet | grep -i "$PLUG_MAC" | awk '{print $1}')

    # 3. Safety Check: If arp-scan failed
    if [ -z "$PLUG_IP" ]; then
        echo "$(date): arp-scan could not find MAC $PLUG_MAC on the network." >> "$ERROR_LOG"
        exit 1
    fi

    # 4. Update the .env file with the confirmed new IP
    if [ "$PLUG_IP" != "$LAST_IP" ]; then
        sed -i "s/LAST_IP=.*/LAST_IP=\"$PLUG_IP\"/" "$SCRIPT_DIR/.env"
        echo "$(date): IP for $PLUG_MAC changed from $LAST_IP to $PLUG_IP. .env updated." >> "$ERROR_LOG"
    fi
fi

# --- 2. Get Wattage ---
# Note: Added 'energy' command fix discussed earlier
WATTAGE=$($KASA_BIN --host "$PLUG_IP" --discovery-timeout 2 --json energy | jq '.power_mw / 1000 | floor' 2>>"$ERROR_LOG")

if [ -z "$WATTAGE" ]; then
    echo "$(date): Could not reach plug at $PLUG_IP" >> "$ERROR_LOG"
    exit 1
fi

# --- 3. Cooldown Logic ---
if [ -f "$LOCK_FILE" ]; then
    LAST_ALERT=$(stat -c %Y "$LOCK_FILE")
    NOW=$(date +%s)
    DIFF=$(( (NOW - LAST_ALERT) / 60 ))
    if [ "$DIFF" -lt "$COOLDOWN_MINUTES" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$WATTAGE,COOLDOWN" >> "$LOG_FILE"
        exit 0
    fi
fi

# --- 4. Alerting ---
if [ "$WATTAGE" -gt "$THRESHOLD" ]; then
    MESSAGE="⚠️ **Power Spike Detected** ⚠️\nDraw: **${WATTAGE}W** (Limit: ${THRESHOLD}W)"
    curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$MESSAGE\"}" "$WEBHOOK_URL"
    touch "$LOCK_FILE"
fi

# --- 5. Log & Cleanup ---
echo "$(date '+%Y-%m-%d %H:%M:%S'),$WATTAGE" >> "$LOG_FILE"
HEADER="Timestamp,Wattage,Status"
DATA=$(grep -v "Timestamp" "$LOG_FILE" | tail -n 10000)
echo -e "$HEADER\n$DATA" > "$LOG_FILE"

# --- 6. Uptime Kuma monitor ---
if [ -n "$KUMA_URL" ]; then
    FULL_KUMA_URL="${KUMA_URL}?status=up&msg=OK&ping=$WATTAGE"
    curl --max-time 10 --retry 3 --retry-delay 5 -s "$FULL_KUMA_URL" > /dev/null
else
    echo "KUMA_URL not found in .env, skipping Kuma push."
fi
