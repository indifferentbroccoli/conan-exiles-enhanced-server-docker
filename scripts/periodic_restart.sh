#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

PERIODIC_RESTART_EVERY_HOURS="${PERIODIC_RESTART_EVERY_HOURS:-0}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"
RETRY_INTERVAL_SECONDS=600
MARKER_FILE="/home/steam/server-files/.periodic_restart_last"

if ! [[ "$PERIODIC_RESTART_EVERY_HOURS" =~ ^[0-9]+$ ]] || [ "$PERIODIC_RESTART_EVERY_HOURS" -lt 0 ] || [ "$PERIODIC_RESTART_EVERY_HOURS" -gt 24 ]; then
    LogError "Periodic restart: PERIODIC_RESTART_EVERY_HOURS must be 0 (disabled) or between 1 and 24. Got '$PERIODIC_RESTART_EVERY_HOURS'."
    exit 1
fi

if [ "$PERIODIC_RESTART_EVERY_HOURS" -eq 0 ]; then
    LogInfo "Periodic restart: disabled (PERIODIC_RESTART_EVERY_HOURS=0)."
    exit 0
fi

INTERVAL_SECONDS=$(( PERIODIC_RESTART_EVERY_HOURS * 3600 ))

get_players_online() {
    local output
    output=$(rcon --address "127.0.0.1:$RCON_PORT" --password "$RCON_PASSWORD" "listplayers" 2>/dev/null || true)

    if [ -z "$output" ]; then
        # Conservative fallback: unknown state, avoid disruptive restart.
        echo 1
        return
    fi

    if echo "$output" | grep -qiE "no players|no players connected|0 players"; then
        echo 0
        return
    fi

    local count
    count=$(echo "$output" | awk '
        /^[[:space:]]*[0-9]+[[:space:]]/ { c++ }
        /^[[:space:]]*[0-9]+\|/ { c++ }
        END { print c + 0 }
    ')

    if [ "$count" -gt 0 ]; then
        echo "$count"
        return
    fi

    # Non-empty but unrecognized format: assume at least one player.
    echo 1
}

# Always reset baseline timer at scheduler start.
# This ensures manual container/server restarts reset the periodic window cleanly.
date +%s > "$MARKER_FILE"

LogAction "Periodic restart scheduler started (every=${PERIODIC_RESTART_EVERY_HOURS}h, retry=${RETRY_INTERVAL_SECONDS}s)"

while true; do
    now_epoch=$(date +%s)
    last_restart_epoch=$(cat "$MARKER_FILE" 2>/dev/null || echo "$now_epoch")

    next_due_epoch=$(( last_restart_epoch + INTERVAL_SECONDS ))
    if [ "$now_epoch" -lt "$next_due_epoch" ]; then
        sleep 60
        continue
    fi

    players_online=$(get_players_online)
    if [ "$players_online" -eq 0 ]; then
        LogAction "Periodic restart: no players online. Restarting server now."
        date +%s > "$MARKER_FILE"

        server_pid=$(pgrep -f "ConanSandboxServer-Linux-Shipping" || true)
        if [ -n "$server_pid" ]; then
            kill -SIGTERM "$server_pid"
        else
            LogWarn "Periodic restart: server process not found."
        fi

        # Exit after triggering restart; new container instance will launch fresh scheduler.
        exit 0
    fi

    LogAction "Periodic restart deferred: ${players_online} player(s) online. Retrying in ${RETRY_INTERVAL_SECONDS}s."
    sleep "$RETRY_INTERVAL_SECONDS"
done
