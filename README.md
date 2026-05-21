![marketing_assets_banner](https://github.com/user-attachments/assets/b8b4ae5c-06bb-46a7-8d94-903a04595036)
[![GitHub License](https://img.shields.io/github/license/indifferentbroccoli/conan-exiles-enhanced-server-docker?style=for-the-badge&color=6aa84f)](https://github.com/indifferentbroccoli/conan-exiles-enhanced-server-docker/blob/main/LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/indifferentbroccoli/conan-exiles-enhanced-server-docker?style=for-the-badge&color=6aa84f)](https://github.com/indifferentbroccoli/conan-exiles-enhanced-server-docker/releases)
[![GitHub Repo stars](https://img.shields.io/github/stars/indifferentbroccoli/conan-exiles-enhanced-server-docker?style=for-the-badge&color=6aa84f)](https://github.com/indifferentbroccoli/conan-exiles-enhanced-server-docker)
[![Discord](https://img.shields.io/discord/798321161082896395?style=for-the-badge&label=Discord&labelColor=5865F2&color=6aa84f)](https://discord.gg/indifferentbroccoli)
[![Docker Pulls](https://img.shields.io/docker/pulls/indifferentbroccoli/conan-exiles-enhanced-server-docker?style=for-the-badge&color=6aa84f)](https://hub.docker.com/r/indifferentbroccoli/conan-exiles-enhanced-server-docker)

Game server hosting — Fast RAM, high-speed internet — Eat lag for breakfast

[Try our Conan Exiles server hosting free for 2 days!](https://indifferentbroccoli.com/conan-exiles-server-hosting)

## Conan Exiles Enhanced Dedicated Server Docker

A Docker container for running a Conan Exiles Enhanced dedicated server using DepotDownloader.

Conan Exiles Enhanced is the Unreal Engine 5 upgrade of Conan Exiles, with stunning visuals and improved performance.

## Server Requirements

| Resource | Minimum  | Recommended |
|----------|----------|-------------|
| CPU      | 2 cores  | 4+ cores    |
| RAM      | 8GB      | 16GB        |
| Storage  | 25GB     | 50GB        |

## How to use

Copy the `.env.example` file to a new file called `.env`. Then use either `docker compose` or `docker run`.

### Docker Compose

```yaml
services:
  conan-exiles-enhanced:
    image: indifferentbroccoli/conan-exiles-enhanced-server-docker
    restart: unless-stopped
    container_name: conan-exiles-enhanced
    stop_grace_period: 30s
    ports:
      - 7777:7777/udp
      - 7778:7778/udp
      - 27015:27015/udp
      - 25575:25575/tcp
    env_file:
      - .env
    volumes:
      - ./server-files:/home/steam/server-files
```

Then run:

```bash
docker compose up -d
```

### Docker Run

```bash
docker run -d \
    --restart unless-stopped \
    --name conan-exiles-enhanced \
    --stop-timeout 30 \
    -p 7777:7777/udp \
    -p 7778:7778/udp \
    -p 27015:27015/udp \
    -p 25575:25575/tcp \
    --env-file .env \
    -v ./server-files:/home/steam/server-files \
    indifferentbroccoli/conan-exiles-enhanced-server-docker
```

## Environment Variables

| Variable        | Default | Info |
|-----------------|---------|------|
| PUID            | 1000    | User ID for file permissions |
| PGID            | 1000    | Group ID for file permissions |
| PORT            | 7777    | UDP port the server listens on (pinger port is always PORT+1) |
| QUERY_PORT      | 27015   | UDP port for Steam server browser queries |
| RCON_PORT       | 25575   | TCP port for RCON |
| MAX_PLAYERS     | 40      | Maximum number of players allowed on the server |
| UPDATE_ON_START | true    | Set to `false` to skip downloading and validating server files on startup |
| SERVER_NAME     | Conan Exiles Enhanced Server | Name shown in the server browser |
| SERVER_PASSWORD |         | Leave blank for a public server |
| RCON_PASSWORD   |         | Password for RCON connections |
| ADMIN_PASSWORD  |         | Server admin password |
| MODS            |         | Comma-separated Steam Workshop mod IDs (e.g. `880454836,1159180273`) |

### Mod Watchdog

| Variable                   | Default | Info                                                                                                                     |
| -------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------ |
| MOD_WATCHDOG_ENABLED       | false   | Set to `true` to enable automatic mod update detection and server restart. Requires `UPDATE_ON_START=true`               |
| MOD_WATCHDOG_INTERVAL      | 600     | How often (in seconds) to check Steam Workshop for mod updates                                                           |
| MOD_WATCHDOG_RESTART_DELAY | 300     | Seconds to wait before restarting after an update is detected. Countdown announcements are broadcast to players via RCON |

When `MOD_WATCHDOG_ENABLED=true` and `MODS` is set, the watchdog runs in the background and periodically queries the Steam Workshop API for each configured mod. If a newer version is detected, it:

1. Broadcasts a restart warning to all connected players via RCON (requires `RCON_PASSWORD` to be set).
2. Sends countdown announcements at regular intervals until `MOD_WATCHDOG_RESTART_DELAY` elapses.
3. Gracefully stops the server; Docker's `restart: unless-stopped` policy then restarts the container, which re-downloads the updated mod(s) before launching the server again.

> **Important:** `UPDATE_ON_START` must be `true` (the default) when using the mod watchdog. If it is `false`, mods will not be re-downloaded on container restart, causing the watchdog to detect the same update on every start and loop indefinitely. The watchdog will refuse to start and log an error if this condition is detected.

## Port Forwarding

Forward these ports through your firewall/router:

| Port  | Protocol | Purpose                        |
|-------|----------|--------------------------------|
| 7777  | UDP      | Game traffic                   |
| 7778  | UDP      | Pinger port (always PORT+1)    |
| 27015 | UDP      | Steam server browser           |
| 25575 | TCP      | RCON                           |

See [portforward.com](https://portforward.com) for router-specific guides.

## Volumes

- `/home/steam/server-files` — Server installation files, saves, and configuration
