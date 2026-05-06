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

if [ -n "${MODS}" ]; then
    LogAction "Installing mods"
    MODS_DIR="$SERVER_FILES/ConanSandbox/Mods"
    mkdir -p "$MODS_DIR"
    : > "$MODS_DIR/modlist.txt"
    IFS=',' read -ra MOD_IDS <<< "${MODS}"
    for MOD_ID in "${MOD_IDS[@]}"; do
        MOD_ID="${MOD_ID// /}"
        /depotdownloader/DepotDownloader -app 440900 -pubfile "$MOD_ID" -dir "$MODS_DIR/$MOD_ID" -validate
        find "$MODS_DIR/$MOD_ID" -name "*.pak" | while IFS= read -r PAK_FILE; do
            echo "*$(basename "$PAK_FILE")" >> "$MODS_DIR/modlist.txt"
        done
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

if [ -n "${ADMIN_PASSWORD}" ]; then
    ARGS+=("-AdminPassword=${ADMIN_PASSWORD}")
fi

exec "$EXEC" "${ARGS[@]}"
