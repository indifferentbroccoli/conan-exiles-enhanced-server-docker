#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

MODS="${MODS:-}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
MOD_WATCHDOG_INTERVAL="${MOD_WATCHDOG_INTERVAL:-3600}"
MOD_WATCHDOG_RESTART_DELAY="${MOD_WATCHDOG_RESTART_DELAY:-300}"

MODS_DIR="/home/steam/server-files/ConanSandbox/Mods"
TIMESTAMPS_FILE="$MODS_DIR/.mod_timestamps"

# Exit early if no mods are configured
if [ -z "$MODS" ]; then
    LogWarn "Mod watchdog: MODS is empty, nothing to watch. Exiting."
    exit 0
fi

# Query the Steam Workshop API for a mod's current time_updated timestamp.
# Prints the Unix timestamp on success, or nothing on failure.
get_workshop_timestamp() {
    local mod_id="$1"
    curl -sf -X POST \
        "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
        --data "itemcount=1&publishedfileids[0]=${mod_id}" \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ts = d['response']['publishedfiledetails'][0].get('time_updated', 0)
    if ts:
        print(ts)
except Exception:
    pass
" 2>/dev/null
}

# Read the stored timestamp for a mod from the timestamps file.
get_stored_timestamp() {
    local mod_id="$1"
    if [ -f "$TIMESTAMPS_FILE" ]; then
        grep "^${mod_id}=" "$TIMESTAMPS_FILE" | cut -d'=' -f2
    fi
}

# Write or update a mod's timestamp in the timestamps file.
store_timestamp() {
    local mod_id="$1"
    local timestamp="$2"
    mkdir -p "$MODS_DIR"
    if [ -f "$TIMESTAMPS_FILE" ] && grep -q "^${mod_id}=" "$TIMESTAMPS_FILE"; then
        sed -i "s|^${mod_id}=.*|${mod_id}=${timestamp}|" "$TIMESTAMPS_FILE"
    else
        echo "${mod_id}=${timestamp}" >> "$TIMESTAMPS_FILE"
    fi
}

# Send a broadcast message via RCON. Fails silently if RCON is not configured.
send_rcon_broadcast() {
    local message="$1"
    if [ -z "$RCON_PASSWORD" ]; then
        return 0
    fi
    python3 /home/steam/server/rcon.py \
        "127.0.0.1" "$RCON_PORT" "$RCON_PASSWORD" \
        "broadcast $message" 2>/dev/null || true
}

# Check all configured mods for Steam Workshop updates.
# Returns 0 (true) if at least one update is detected, 1 otherwise.
check_for_updates() {
    local updates_found=false

    IFS=',' read -ra MOD_IDS <<< "$MODS"
    for MOD_ID in "${MOD_IDS[@]}"; do
        MOD_ID="${MOD_ID// /}"
        [ -z "$MOD_ID" ] && continue

        local current_ts
        current_ts=$(get_workshop_timestamp "$MOD_ID")

        if [ -z "$current_ts" ]; then
            LogWarn "Mod watchdog: Could not fetch timestamp for mod $MOD_ID, skipping."
            continue
        fi

        local stored_ts
        stored_ts=$(get_stored_timestamp "$MOD_ID")

        if [ -z "$stored_ts" ]; then
            LogInfo "Mod watchdog: No stored timestamp for mod $MOD_ID, recording current."
            store_timestamp "$MOD_ID" "$current_ts"
            continue
        fi

        if [ "$current_ts" -gt "$stored_ts" ]; then
            LogAction "Mod watchdog: Update detected for mod $MOD_ID (stored=$stored_ts, latest=$current_ts)"
            updates_found=true
        fi
    done

    $updates_found
}

# Send countdown RCON announcements and then terminate the server process.
# Docker's restart policy will bring the container back up, re-downloading mods.
do_restart() {
    local delay="$MOD_WATCHDOG_RESTART_DELAY"
    LogAction "Mod watchdog: Mod update(s) detected. Server will restart in ${delay}s."

    # Initial announcement
    if [ "$delay" -ge 60 ]; then
        local mins=$(( delay / 60 ))
        send_rcon_broadcast "Server will restart for mod updates in ${mins} minute(s)."
    else
        send_rcon_broadcast "Server will restart for mod updates in ${delay} second(s)."
    fi

    # Countdown checkpoints (seconds remaining before restart)
    local checkpoints=(1800 900 600 300 180 60 30 10)
    local remaining="$delay"

    for checkpoint in "${checkpoints[@]}"; do
        if [ "$remaining" -gt "$checkpoint" ]; then
            sleep $(( remaining - checkpoint ))
            remaining="$checkpoint"
            if [ "$checkpoint" -ge 60 ]; then
                local mins=$(( checkpoint / 60 ))
                send_rcon_broadcast "Server restart in ${mins} minute(s)."
            else
                send_rcon_broadcast "Server restart in ${checkpoint} second(s)."
            fi
            LogInfo "Mod watchdog: Restart in ${checkpoint}s"
        fi
    done

    # Final wait
    if [ "$remaining" -gt 0 ]; then
        sleep "$remaining"
    fi

    send_rcon_broadcast "Server is restarting now for mod updates. Please reconnect shortly."
    LogAction "Mod watchdog: Initiating server restart."

    local pid
    pid=$(pgrep -f "ConanSandboxServer-Linux-Shipping")
    if [ -n "$pid" ]; then
        kill -SIGTERM "$pid"
    else
        LogWarn "Mod watchdog: Server process not found during restart attempt."
    fi
}

# Allow the server time to start before the first check
LogAction "Mod watchdog started (interval=${MOD_WATCHDOG_INTERVAL}s, restart_delay=${MOD_WATCHDOG_RESTART_DELAY}s)"
sleep 60

while true; do
    if check_for_updates; then
        do_restart
        # Exit after triggering restart; the new container instance starts a fresh watchdog
        exit 0
    fi
    sleep "$MOD_WATCHDOG_INTERVAL"
done
