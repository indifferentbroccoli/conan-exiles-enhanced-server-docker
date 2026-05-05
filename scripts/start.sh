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

EXEC="$SERVER_FILES/ConanSandboxServer.sh"

if [ ! -f "$EXEC" ]; then
    LogError "Could not find server executable at: $EXEC"
    exit 1
fi

chmod +x "$EXEC"
LogInfo "Server starting on port ${PORT}, query port ${QUERY_PORT}"

exec "$EXEC" \
    /Game/Maps/ConanSandbox/ConanSandbox \
    "-port=${PORT}" \
    "-queryport=${QUERY_PORT}" \
    "-RconPort=${RCON_PORT}" \
    "-MaxPlayers=${MAX_PLAYERS}" \
    "-ServerName=${SERVER_NAME}" \
    "-ServerPassword=${SERVER_PASSWORD}" \
    -server \
    -log
