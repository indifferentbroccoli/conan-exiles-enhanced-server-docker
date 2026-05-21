# BUILD THE SERVER IMAGE
FROM --platform=linux/amd64 debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    unzip \
    procps \
    libicu-dev \
    libssl3 \
    libcurl4 \
    gettext-base \
    crudini \
    jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install .NET 8 runtime (required for DepotDownloader)
RUN curl -sL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet && \
    ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet && \
    rm /tmp/dotnet-install.sh

# Download rcon-cli
ARG RCON_CLI_VERSION=0.10.3
ARG RCON_CLI_SHA256=6962a641ebf9a5957bd0cda1b8acf3e34a23686ae709f6c6a14ac3898521a5cc
RUN curl -sL \
    "https://github.com/gorcon/rcon-cli/releases/download/v${RCON_CLI_VERSION}/rcon-${RCON_CLI_VERSION}-amd64_linux.tar.gz" \
    -o /tmp/rcon.tar.gz && \
    echo "${RCON_CLI_SHA256}  /tmp/rcon.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/rcon.tar.gz --strip-components=1 -C /usr/local/bin \
    "rcon-${RCON_CLI_VERSION}-amd64_linux/rcon" && \
    chmod +x /usr/local/bin/rcon && \
    rm /tmp/rcon.tar.gz

# Download DepotDownloader
ARG DEPOT_DOWNLOADER_VERSION=3.4.0
RUN curl -sL \
    "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOT_DOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" \
    -o /tmp/dd.zip && \
    mkdir -p /depotdownloader && \
    unzip /tmp/dd.zip -d /depotdownloader && \
    chmod +x /depotdownloader/DepotDownloader && \
    rm /tmp/dd.zip

RUN useradd -m -s /bin/bash steam

ENV HOME=/home/steam \
    PORT=7777 \
    QUERY_PORT=27015 \
    RCON_PORT=25575 \
    UPDATE_ON_START=true \
    MAX_PLAYERS=40 \
    SERVER_NAME="Conan Exiles Enhanced Server" \
    SERVER_PASSWORD="" \
    RCON_PASSWORD="" \
    ADMIN_PASSWORD="" \
    MODS="" \
    MOD_WATCHDOG_ENABLED=false \
    MOD_WATCHDOG_INTERVAL=3600 \
    MOD_WATCHDOG_RESTART_DELAY=300

COPY ./scripts /home/steam/server/

COPY branding /branding

RUN mkdir -p /home/steam/server-files && \
    chmod +x /home/steam/server/*.sh

WORKDIR /home/steam/server

HEALTHCHECK --start-period=5m \
    CMD pgrep -f "ConanSandboxServer-Linux-Shipping" > /dev/null || exit 1

ENTRYPOINT ["/home/steam/server/init.sh"]
