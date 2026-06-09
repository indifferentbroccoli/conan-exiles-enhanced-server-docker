#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

SERVER_FILES="/home/steam/server-files"
WATCHDOG_READY_FILE="$SERVER_FILES/.watchdog_ready"

cd "$SERVER_FILES" || exit

# Clear previous readiness marker; it will be recreated once mod baseline refresh completes.
rm -f "$WATCHDOG_READY_FILE"

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

# Steam App IDs are fixed for Conan Exiles dedicated server registration.
STEAM_APP_ID=440900
STEAM_GAME_ID=440900
export SteamAppId="$STEAM_APP_ID"
export SteamGameId="$STEAM_GAME_ID"

# Some engines read this file from working dir or Linux binaries dir.
echo "$STEAM_APP_ID" > "$SERVER_FILES/steam_appid.txt"
mkdir -p "$SERVER_FILES/ConanSandbox/Binaries/Linux"
echo "$STEAM_APP_ID" > "$SERVER_FILES/ConanSandbox/Binaries/Linux/steam_appid.txt"

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
    CLEAN_MOD_IDS=()
    IFS=',' read -ra MOD_IDS <<< "${MODS}"
    for MOD_ID in "${MOD_IDS[@]}"; do
        MOD_ID="${MOD_ID// /}"
        [ -z "$MOD_ID" ] && continue
        CLEAN_MOD_IDS+=("$MOD_ID")
        LogInfo "Downloading mod $MOD_ID..."
        /depotdownloader/DepotDownloader -app 440900 -pubfile "$MOD_ID" -dir "$MODS_DIR/$MOD_ID" -validate > /dev/null 2>&1
        LogInfo "Mod $MOD_ID installed."
        find "$MODS_DIR/$MOD_ID" -name "*.pak" | while IFS= read -r PAK_FILE; do
            echo "*${MOD_ID}\\$(basename "$PAK_FILE")" >> "$MODS_DIR/modlist.txt"
        done
    done

    # Record current Workshop timestamps in a single batched API request for watchdog baseline.
    if [ "${#CLEAN_MOD_IDS[@]}" -gt 0 ]; then
        batch_ts=$(get_workshop_timestamps_batch "${CLEAN_MOD_IDS[@]}")
        declare -A ts_by_mod
        if [ -n "$batch_ts" ]; then
            while IFS='=' read -r id ts; do
                [ -z "$id" ] && continue
                ts_by_mod["$id"]="$ts"
            done <<< "$batch_ts"
        fi

        for MOD_ID in "${CLEAN_MOD_IDS[@]}"; do
            mod_ts="${ts_by_mod[$MOD_ID]:-}"
            if [ -n "$mod_ts" ]; then
                store_timestamp "$MOD_ID" "$mod_ts"
                LogInfo "Mod $MOD_ID timestamp recorded: $mod_ts"
            else
                LogWarn "Could not record baseline timestamp for mod $MOD_ID"
            fi
        done
    fi
fi

# Signal watchdog checks can start after startup/mod baseline refresh is complete.
touch "$WATCHDOG_READY_FILE"

EXEC="$SERVER_FILES/ConanSandboxServer.sh"

if [ ! -f "$EXEC" ]; then
    LogError "Could not find server executable at: $EXEC"
    exit 1
fi

chmod +x "$EXEC"
LogInfo "Server starting on port ${PORT}, query port ${QUERY_PORT}"
LogInfo "Steam AppID config: SteamAppId=${SteamAppId}, SteamGameId=${SteamGameId}"

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
