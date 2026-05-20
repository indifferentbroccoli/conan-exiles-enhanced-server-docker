#!/bin/bash
# shellcheck source=scripts/functions.sh
source "/home/steam/server/functions.sh"

LogAction "Set file permissions"

if [ -z "${PUID}" ] || [ -z "${PGID}" ]; then
    LogError "PUID and PGID not set. Please set these in the environment variables."
    exit 1
else
    usermod -o -u "${PUID}" steam
    groupmod -o -g "${PGID}" steam
fi

chown -R steam:steam /home/steam/

cat /branding

if [ "${UPDATE_ON_START:-true}" = "true" ]; then
    install
else
    LogWarn "UPDATE_ON_START is set to false, skipping server update"
fi

chown -R steam:steam /home/steam/server-files

# shellcheck disable=SC2317
term_handler() {
    if ! shutdown_server; then
        kill -SIGTERM "$(pgrep -f ConanSandboxServer-Linux-Shipping)"
    fi
    tail --pid="$killpid" -f 2>/dev/null
}

trap 'term_handler' SIGTERM

# Start the server as steam user
su - steam -c "cd /home/steam/server && \
    PORT='${PORT}' \
    QUERY_PORT='${QUERY_PORT}' \
    RCON_PORT='${RCON_PORT}' \
    MAX_PLAYERS='${MAX_PLAYERS}' \
    SERVER_NAME='${SERVER_NAME}' \
    SERVER_PASSWORD='${SERVER_PASSWORD}' \
    RCON_PASSWORD='${RCON_PASSWORD}' \
    ADMIN_PASSWORD='${ADMIN_PASSWORD}' \
    MODS='${MODS}' \
    ./start.sh" &

killpid="$!"

# Start the mod watchdog as steam user if enabled and mods are configured
if [ "${MOD_WATCHDOG_ENABLED:-false}" = "true" ] && [ -n "${MODS}" ]; then
    if [ "${UPDATE_ON_START:-true}" != "true" ]; then
        LogError "Mod watchdog requires UPDATE_ON_START=true. When UPDATE_ON_START is false, mods are not re-downloaded on restart, causing an infinite restart loop. Watchdog will not start."
    else
        su - steam -c "cd /home/steam/server && \
            MODS='${MODS}' \
            RCON_PORT='${RCON_PORT}' \
            RCON_PASSWORD='${RCON_PASSWORD}' \
            MOD_WATCHDOG_INTERVAL='${MOD_WATCHDOG_INTERVAL:-3600}' \
            MOD_WATCHDOG_RESTART_DELAY='${MOD_WATCHDOG_RESTART_DELAY:-300}' \
            ./mod_watchdog.sh" &
    fi
fi

wait "$killpid"
