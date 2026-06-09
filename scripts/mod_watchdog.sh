#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

MODS="${MODS:-}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
MOD_WATCHDOG_INTERVAL="${MOD_WATCHDOG_INTERVAL:-600}"
MOD_WATCHDOG_RESTART_DELAY="${MOD_WATCHDOG_RESTART_DELAY:-300}"
MOD_WATCHDOG_INITIAL_GRACE=3600

MODS_DIR="/home/steam/server-files/ConanSandbox/Mods"
TIMESTAMPS_FILE="$MODS_DIR/.mod_timestamps"
WATCHDOG_READY_FILE="/home/steam/server-files/.watchdog_ready"

# Exit early if no mods are configured
if [ -z "$MODS" ]; then
    LogWarn "Mod watchdog: MODS is empty, nothing to watch. Exiting."
    exit 0
fi

# Check all configured mods for Steam Workshop updates.
# Returns 0 (true) if at least one update is detected, 1 otherwise.
check_for_updates() {
    local found=1
    local mod_ids=()

    IFS=',' read -ra MOD_IDS <<< "$MODS"
    for MOD_ID in "${MOD_IDS[@]}"; do
        MOD_ID="${MOD_ID// /}"
        [ -z "$MOD_ID" ] && continue
        mod_ids+=("$MOD_ID")
    done

    if [ "${#mod_ids[@]}" -eq 0 ]; then
        LogWarn "Mod watchdog: MODS contains no valid IDs after parsing, skipping check."
        return 1
    fi

    # Fetch all current timestamps in a single API call.
    local batch_output
    batch_output=$(get_workshop_timestamps_batch "${mod_ids[@]}")

    declare -A current_ts_by_mod
    if [ -n "$batch_output" ]; then
        while IFS='=' read -r id ts; do
            [ -z "$id" ] && continue
            current_ts_by_mod["$id"]="$ts"
        done <<< "$batch_output"
    fi

    for MOD_ID in "${mod_ids[@]}"; do

        local current_ts
        current_ts="${current_ts_by_mod[$MOD_ID]}"

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
            found=0
        fi
    done

    return "$found"
}

# Send countdown RCON announcements and then terminate the server process.
# Docker's restart policy will bring the container back up, re-downloading mods.
do_restart() {
    local delay="$MOD_WATCHDOG_RESTART_DELAY"
    LogAction "Mod watchdog: Mod update(s) detected. Server will restart in ${delay}s."

    # Initial announcement
    if [ "$delay" -ge 60 ]; then
        local minutes=$(( delay / 60 ))
        send_rcon_broadcast "Server will restart for mod updates in ${minutes} minute(s)."
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
                local minutes=$(( checkpoint / 60 ))
                send_rcon_broadcast "Server restart in ${minutes} minute(s)."
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

# Wait until startup has completed mod baseline timestamp refresh.
LogAction "Mod watchdog started (interval=${MOD_WATCHDOG_INTERVAL}s, restart_delay=${MOD_WATCHDOG_RESTART_DELAY}s)"
LogAction "Mod watchdog: Waiting for startup readiness marker before first check."
while [ ! -f "$WATCHDOG_READY_FILE" ]; do
    sleep 5
done

# Give the game server a short grace period after startup readiness.
LogAction "Mod watchdog: Startup ready. Waiting initial grace period (${MOD_WATCHDOG_INITIAL_GRACE}s)."
sleep "$MOD_WATCHDOG_INITIAL_GRACE"

while true; do
    LogAction "Mod watchdog: Running update check for configured mods (single batched API call)."
    if check_for_updates; then
        LogAction "Mod watchdog: Update(s) detected. Restart sequence will begin."
        do_restart
        # Exit after triggering restart; the new container instance starts a fresh watchdog
        exit 0
    else
        LogAction "Mod watchdog: No updates detected in this check cycle."
    fi
    sleep "$MOD_WATCHDOG_INTERVAL"
done
