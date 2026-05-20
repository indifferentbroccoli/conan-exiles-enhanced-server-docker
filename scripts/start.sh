#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

SERVER_FILES="/home/steam/server-files"

cd "$SERVER_FILES" || exit

LogAction "Starting Conan Exiles Enhanced Dedicated Server"

PORT="${PORT:-7777}"
QUERY_PORT="${QUERY_PORT:-27015}"
RCON_PORT="${RCON_PORT:-25575}"
MAX_PLAYERS="${MAX_PLAYERS:-40}"
SERVER_NAME="${SERVER_NAME:-Conan Exiles Enhanced Server}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
RCON_PASSWORD="${RCON_PASSWORD:-}"

ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
MODS="${MODS:-}"

CONFIG_DIR="$SERVER_FILES/ConanSandbox/Saved/Config/LinuxServer"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/Game.ini" << EOF
[RconPlugin]
RconEnabled=1
RconPassword=${RCON_PASSWORD}
RconPort=${RCON_PORT}
EOF

if [ -n "${ADMIN_PASSWORD}" ]; then
    set_ini_value "$CONFIG_DIR/ServerSettings.ini" "ServerSettings" "AdminPassword" "${ADMIN_PASSWORD}"
fi

if [ -n "${MODS}" ]; then
    LogAction "Installing mods"
    MODS_DIR="$SERVER_FILES/ConanSandbox/Mods"
    mkdir -p "$MODS_DIR"
    TIMESTAMPS_FILE="$MODS_DIR/.mod_timestamps"
    : > "$MODS_DIR/modlist.txt"
    IFS=',' read -ra MOD_IDS <<< "${MODS}"
    for MOD_ID in "${MOD_IDS[@]}"; do
        MOD_ID="${MOD_ID// /}"
        LogInfo "Downloading mod $MOD_ID..."
        /depotdownloader/DepotDownloader -app 440900 -pubfile "$MOD_ID" -dir "$MODS_DIR/$MOD_ID" -validate > /dev/null 2>&1
        LogInfo "Mod $MOD_ID installed."
        find "$MODS_DIR/$MOD_ID" -name "*.pak" | while IFS= read -r PAK_FILE; do
            echo "*${MOD_ID}\\$(basename "$PAK_FILE")" >> "$MODS_DIR/modlist.txt"
        done
        # Store the current Steam Workshop timestamp so the mod watchdog has a baseline
        MOD_TS=$(curl -sf -X POST \
            "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
            --data "itemcount=1&publishedfileids[0]=${MOD_ID}" \
            | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ts = d['response']['publishedfiledetails'][0].get('time_updated', 0)
    if ts:
        print(ts)
except Exception:
    pass
" 2>/dev/null)
        if [ -n "$MOD_TS" ]; then
            if [ -f "$TIMESTAMPS_FILE" ] && grep -q "^${MOD_ID}=" "$TIMESTAMPS_FILE"; then
                sed -i "s|^${MOD_ID}=.*|${MOD_ID}=${MOD_TS}|" "$TIMESTAMPS_FILE"
            else
                echo "${MOD_ID}=${MOD_TS}" >> "$TIMESTAMPS_FILE"
            fi
            LogInfo "Mod $MOD_ID timestamp recorded: $MOD_TS"
        fi
    done
fi

EXEC="$SERVER_FILES/ConanSandboxServer.sh"

if [ ! -f "$EXEC" ]; then
    LogError "Could not find server executable at: $EXEC"
    exit 1
fi

chmod +x "$EXEC"
LogInfo "Server starting on port ${PORT}, query port ${QUERY_PORT}"

ARGS=(
    /Game/Maps/ConanSandbox/ConanSandbox
    "-port=${PORT}"
    "-queryport=${QUERY_PORT}"
    "-MaxPlayers=${MAX_PLAYERS}"
    "-ServerName=${SERVER_NAME}"
    -server
    -log
)

if [ -n "${SERVER_PASSWORD}" ]; then
    ARGS+=("-ServerPassword=${SERVER_PASSWORD}")
fi

exec "$EXEC" "${ARGS[@]}"
