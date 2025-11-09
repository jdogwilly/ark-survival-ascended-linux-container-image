# Pelican Panel Implementation Reference - Code Deep Dive

**Purpose**: Detailed code snippets and implementation patterns from Pelican Panel's working ARK SA setup

---

## Table of Contents

1. [Complete Dockerfile](#complete-dockerfile)
2. [Complete Entrypoint Script](#complete-entrypoint-script)
3. [Installation Script](#installation-script)
4. [Egg Configuration](#egg-configuration)
5. [Key Code Patterns](#key-code-patterns)
6. [Environment Variable Patterns](#environment-variable-patterns)
7. [Directory Structure](#directory-structure)
8. [SteamCMD Command Patterns](#steamcmd-command-patterns)

---

## Complete Dockerfile

**Source**: `ghcr.io/parkervcp/steamcmd:proton`
**Location**: `parkervcp/yolks/steamcmd/proton/Dockerfile`

```dockerfile
# Steam Proton image
FROM debian:bookworm-slim

LABEL author="Torsten Widmann" maintainer="info@goover.de"

# Install required packages
RUN dpkg --add-architecture i386

# Core system packages
RUN apt update && apt install -y --no-install-recommends \
    wget \
    iproute2 \
    gnupg2 \
    software-properties-common \
    libntlm0 \
    winbind \
    xvfb \
    xauth \
    libncurses5-dev:i386 \
    libncurses6 \
    dbus \
    libgdiplus \
    lib32gcc-s1

# Audio and codec support
RUN apt install -y \
    alsa-tools \
    libpulse0 \
    pulseaudio \
    libpulse-dev \
    libasound2 \
    libao-common \
    gnutls-bin \
    gnupg \
    locales \
    cabextract \
    curl \
    python3 \
    python3-pip \
    python3-setuptools \
    tini \
    file \
    pipx

# Download Proton GE (Latest)
RUN curl -sLOJ "$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | egrep .tar.gz)"
RUN tar -xzf GE-Proton*.tar.gz -C /usr/local/bin/ --strip-components=1
RUN rm GE-Proton*.*

# Proton Fix machine-id (CRITICAL)
RUN rm -f /etc/machine-id
RUN dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id
RUN dbus-uuidgen --ensure

# Setup Protontricks
RUN pipx install protontricks

# Set up Winetricks
RUN wget -q -O /usr/sbin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x /usr/sbin/winetricks

# Install rcon
RUN cd /tmp/ \
    && curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz \
    && tar xvf rcon.tar.gz \
    && mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/

# Setup user and working directory
RUN useradd -m -d /home/container -s /bin/bash container
USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

STOPSIGNAL SIGINT

COPY --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
```

### Dockerfile Notes

- **Line 25-26**: Dynamically downloads the LATEST Proton-GE release
- **Line 29-32**: Machine-ID reset is CRITICAL - prevents "unit test mode" errors
- **Line 34-39**: Installs tool ecosystem (protontricks, winetricks, rcon)
- **Line 41-42**: Creates non-root container user for security
- **Line 45**: Uses `tini` as init process for proper signal handling
- **No Wine Installation**: Wine is installed dynamically by Proton-GE during extraction

---

## Complete Entrypoint Script

**Source**: `parkervcp/yolks/steamcmd/entrypoint.sh`

```bash
#!/bin/bash

#
# Copyright (c) 2021 Matthew Penner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# Wait for the container to fully initialize
sleep 1

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Set environment for Steam Proton
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        # Create per-app compatdata directory
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}

        # Set Proton paths
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"

        # Fix for pipx with protontricks
        export PATH=$PATH:/root/.local/bin
    else
        echo -e "----------------------------------------------------------------------------------"
        echo -e "WARNING!!! Proton needs variable SRCDS_APPID, else it will not work. Please add it"
        echo -e "Server stops now"
        echo -e "----------------------------------------------------------------------------------"
        exit 0
    fi
fi

# Switch to the container's working directory
cd /home/container || exit 1

## just in case someone removed the defaults.
if [ "${STEAM_USER}" == "" ]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

## if auto_update is not set or to 1 update
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    # Update Source Server
    if [ ! -z ${SRCDS_APPID} ]; then
        if [ "${STEAM_USER}" == "anonymous" ]; then
            ./steamcmd/steamcmd.sh \
                +force_install_dir /home/container \
                +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
                $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
                +app_update 1007 \
                +app_update ${SRCDS_APPID} \
                $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) \
                $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) \
                $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) \
                ${INSTALL_FLAGS} \
                $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) \
                +quit
        else
            ./steamcmd/steamcmd.sh \
                +force_install_dir /home/container \
                +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
                $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
                +app_update 1007 \
                +app_update ${SRCDS_APPID} \
                $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) \
                $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) \
                $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) \
                ${INSTALL_FLAGS} \
                $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) \
                +quit
        fi
    else
        echo -e "No appid set. Starting Server"
    fi
else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}
```

### Entrypoint Script Key Points

**Lines 31-44**: Proton Setup
- Creates compatdata directory structure
- Sets `STEAM_COMPAT_CLIENT_INSTALL_PATH` pointing to Steam installation
- Sets `STEAM_COMPAT_DATA_PATH` pointing to per-app wine prefix
- Checks that `SRCDS_APPID` is set (required for Proton)

**Lines 47-59**: Steam User Setup
- Defaults to anonymous if no user provided
- Maintains backward compatibility

**Lines 61-80**: SteamCMD Update Logic
- Key line: `+app_update 1007` - Downloads Steam runtime bootstrap
- Followed by: `+app_update ${SRCDS_APPID}` - Downloads the game
- Supports beta versions if specified
- Conditional validation flag

**Lines 82-85**: Startup Execution
- Uses bash variable expansion to replace template variables
- Evaluates the STARTUP command with full variable substitution

---

## Installation Script

**Source**: Pelican eggs ARK SA installation script

```bash
#!/bin/bash
# steamcmd Base Installation Script
#
# Server Files: /mnt/server
# Image to install with is 'ghcr.io/parkervcp/installers:debian'

##
#
# Variables
# STEAM_USER, STEAM_PASS, STEAM_AUTH - Steam user setup
# WINDOWS_INSTALL - if it's a windows server you want to install set to 1
# SRCDS_APPID - steam app id for the game
# SRCDS_BETAID - beta branch of a steam app
# SRCDS_BETAPASS - password for a beta branch
# INSTALL_FLAGS - Any additional SteamCMD flags to pass
# AUTO_UPDATE - Adding this variable allows disabling/enabling auto-updates
#
 ##

## just in case someone removed the defaults.
if [[ "${STEAM_USER}" == "" ]] || [[ "${STEAM_PASS}" == "" ]]; then
    echo -e "steam user is not set.\n"
    echo -e "Using anonymous user.\n"
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
else
    echo -e "user set to ${STEAM_USER}"
fi

## download and install steamcmd
cd /tmp
mkdir -p /mnt/server/steamcmd
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
mkdir -p /mnt/server/steamapps # Fix steamcmd disk write error when this folder is missing
cd /mnt/server/steamcmd

# SteamCMD fails otherwise for some reason, even running as root.
# This is changed at the end of the install process anyways.
chown -R root:root /mnt
export HOME=/mnt/server

## install game using steamcmd
./steamcmd.sh \
    +force_install_dir /mnt/server \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
    +app_update ${SRCDS_APPID} \
    $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) \
    $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) \
    ${INSTALL_FLAGS} \
    validate \
    +quit

## CRITICAL: set up 32 bit libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

## CRITICAL: set up 64 bit libraries
mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so

## add below your custom commands if needed

## cleanup movies (optional for ARK SA)
rm -rf /mnt/server/ShooterGame/Content/Movies

## touch log file
mkdir -p /mnt/server/ShooterGame/Saved/Logs
echo "--fresh install--" >> /mnt/server/ShooterGame/Saved/Logs/ShooterGame.log

## install end
echo "-----------------------------------------"
echo "Installation completed..."
echo "-----------------------------------------"
```

### Installation Script Critical Sections

**Lines 38-55**: SteamCMD Download & Game Installation
```bash
./steamcmd.sh \
    +force_install_dir /mnt/server \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    +@sSteamCmdForcePlatformType windows \
    +app_update ${SRCDS_APPID} \
    validate \
    +quit
```

**Lines 57-63**: CRITICAL Steam Client Library Setup
```bash
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so
```

These lines are **ESSENTIAL**:
- `linux32/steamclient.so` comes from SteamCMD's steamcmd directory
- Gets copied to `../.steam/sdk32/` (parent's .steam directory)
- Proton uses these files to load Windows DLLs
- Missing these causes Proton initialization to fail

---

## Egg Configuration

**File**: `egg-ark--survival-ascended.json`

```json
{
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL",
    "meta": {
        "version": "PTDL_v2",
        "update_url": null
    },
    "exported_at": "2023-11-12T11:57:56+01:00",
    "name": "ARK: Survival Ascended",
    "author": "blood@darkartsgaming.com",
    "description": "ARK is reimagined from the ground-up into the next-generation of video game technology with Unreal Engine 5!",
    "features": [
        "steam_disk_space"
    ],
    "docker_images": {
        "Proton": "ghcr.io/parkervcp/steamcmd:proton"
    },
    "file_denylist": [],
    "startup": "rmv() { echo \"stopping server\"; rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} KeepAlive && rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} DoExit && wait ${ARK_PID}; echo \"Server Closed\"; exit; }; trap rmv 15 2; proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe {{SERVER_MAP}}?listen?MaxPlayers={{MAX_PLAYERS}}?SessionName=\\\"{{SESSION_NAME}}\\\"?Port={{SERVER_PORT}}?QueryPort={{QUERY_PORT}}?RCONPort={{RCON_PORT}}?RCONEnabled=True$( [  \"$SERVER_PVE\" == \"0\" ] || printf %s '?ServerPVE=True' )?ServerPassword=\"{{SERVER_PASSWORD}}\"{{ARGS_PARAMS}}?ServerAdminPassword=\"{{ARK_ADMIN_PASSWORD}}\" -WinLiveMaxPlayers={{MAX_PLAYERS}} -oldconsole -servergamelog$( [ -z \"$MOD_IDS\" ] || printf %s ' -mods=' $MOD_IDS )$( [ \"$BATTLE_EYE\" == \"1\" ] || printf %s ' -NoBattlEye' ) -Port={{SERVER_PORT}} {{ARGS_FLAGS}} & ARK_PID=$! ; tail -c0 -F ./ShooterGame/Saved/Logs/ShooterGame.log --pid=$ARK_PID & until echo \"waiting for rcon connection...\"; (rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD})<&0 & wait $!; do sleep 5; done",
    "config": {
        "files": "{\"ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini\": {\"parser\": \"file\", \"find\": {\"MaxPlayers=\": \"MaxPlayers={{server.build.env.MAX_PLAYERS}}\", \"ServerAdminPassword=\": \"ServerAdminPassword={{server.build.env.ARK_ADMIN_PASSWORD}}\"}}}"
    },
    "startup": "...(as above)...",
    "scripts": {
        "installation": {
            "script": "...(as shown in Installation Script section)...",
            "container": "ghcr.io/parkervcp/installers:debian",
            "entrypoint": "bash"
        }
    },
    "variables": [
        {
            "name": "Server Map",
            "description": "Available Maps: TheIsland_WP",
            "env_variable": "SERVER_MAP",
            "default_value": "TheIsland_WP",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string|max:64",
            "field_type": "text"
        },
        {
            "name": "Server Name",
            "description": "\"Unofficial\" dedicated server name",
            "env_variable": "SESSION_NAME",
            "default_value": "A Pterodactyl Hosted Server",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string|max:256",
            "field_type": "text"
        },
        {
            "name": "Auto-update server",
            "description": "This is to enable auto-updating for servers on restart/re-install.",
            "env_variable": "AUTO_UPDATE",
            "default_value": "1",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Battle Eye",
            "description": "Enable BattlEye / Anti-Cheat",
            "env_variable": "BATTLE_EYE",
            "default_value": "1",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "App ID",
            "description": "app id required for server download/updates",
            "env_variable": "SRCDS_APPID",
            "default_value": "2430930",
            "user_viewable": false,
            "user_editable": false,
            "rules": "required|integer|in:2430930",
            "field_type": "text"
        },
        {
            "name": "Additional Arguments (PARAMS)",
            "description": "params (?ServerPassword=...) are supported here",
            "env_variable": "ARGS_PARAMS",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:1024",
            "field_type": "text"
        },
        {
            "name": "Max Players",
            "description": "Specifies the maximum amount of players able to join the server.",
            "env_variable": "MAX_PLAYERS",
            "default_value": "70",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|integer|min:1|max:200",
            "field_type": "text"
        },
        {
            "name": "Server Admin Password",
            "description": "Used for RCON (remote and in-browser console)",
            "env_variable": "ARK_ADMIN_PASSWORD",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|alpha_dash|max:128",
            "field_type": "text"
        },
        {
            "name": "Query Port",
            "description": "ARK query port used by steam server browser",
            "env_variable": "QUERY_PORT",
            "default_value": "27015",
            "user_viewable": true,
            "user_editable": false,
            "rules": "required|integer|min:1025|max:65535",
            "field_type": "text"
        },
        {
            "name": "Additional Arguments (FLAGS)",
            "description": "flags (-UseBattlEye) are supported here",
            "env_variable": "ARGS_FLAGS",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:1024",
            "field_type": "text"
        },
        {
            "name": "Server PvE",
            "description": "ON = PvE, OFF = PvP; Default is ON",
            "env_variable": "SERVER_PVE",
            "default_value": "1",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Server Password",
            "description": "required password to enter the server, leave blank for public",
            "env_variable": "SERVER_PASSWORD",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|alpha_dash|max:128",
            "field_type": "text"
        },
        {
            "name": "RCON Port",
            "description": "required for console commands and proper shutdown",
            "env_variable": "RCON_PORT",
            "default_value": "37015",
            "user_viewable": true,
            "user_editable": false,
            "rules": "required|integer|min:1025|max:65535",
            "field_type": "text"
        },
        {
            "name": "MOD IDs",
            "description": "CurseForge mod IDs; separate by comma ( , ) without spaces",
            "env_variable": "MOD_IDS",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:512",
            "field_type": "text"
        }
    ]
}
```

---

## Key Code Patterns

### Pattern 1: Proton Detection and Setup

```bash
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
    else
        echo "ERROR: SRCDS_APPID not set"
        exit 0
    fi
fi
```

**What it does:**
1. Checks if Proton binary exists
2. Verifies SRCDS_APPID is set
3. Creates per-game Wine prefix directory
4. Sets environment variables for Proton to find Steam and the prefix

### Pattern 2: Conditional Bash Variable Expansion

```bash
$( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' )
```

**What it does:**
- If `WINDOWS_INSTALL` is "1", returns `+@sSteamCmdForcePlatformType windows`
- Otherwise, returns nothing
- Used to conditionally add SteamCMD flags

**Used for:**
- BATTLE_EYE flag: `$( [ "$BATTLE_EYE" == "1" ] || printf %s ' -NoBattlEye' )`
- MOD_IDS: `$( [ -z "$MOD_IDS" ] || printf %s ' -mods=' $MOD_IDS )`
- PVE mode: `$( [ "$SERVER_PVE" == "0" ] || printf %s '?ServerPVE=True' )`

### Pattern 3: Graceful Shutdown Handler

```bash
rmv() {
    echo "stopping server";
    rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} KeepAlive && \
    rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} DoExit && \
    wait ${ARK_PID};
    echo "Server Closed";
    exit;
}
trap rmv 15 2
```

**What it does:**
1. Defines function `rmv()` that will be called on SIGTERM (15) or SIGINT (2)
2. Sends RCON KeepAlive command to ensure connection
3. Sends RCON DoExit command to shutdown the server gracefully
4. Waits for process to exit
5. Exits the container

### Pattern 4: Background Process with PID Capture

```bash
proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe [args] &
ARK_PID=$!
```

**What it does:**
- Launches Proton in background
- Captures the process ID
- Allows monitoring or sending signals to the process

### Pattern 5: Log Streaming with PID Following

```bash
tail -c0 -F ./ShooterGame/Saved/Logs/ShooterGame.log --pid=$ARK_PID &
```

**What it does:**
- `-c0`: Start from end of file (skip existing content)
- `-F`: Follow file (continue reading new lines)
- `--pid=$ARK_PID`: Stop following if main process exits
- `&`: Run in background

### Pattern 6: Readiness Check Loop

```bash
until echo "waiting for rcon connection..."; \
    (rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD})<&0 & \
    wait $!; \
do sleep 5; done
```

**What it does:**
1. Prints "waiting for rcon connection..." each attempt
2. Tries to execute RCON (any command works for checking)
3. Captures exit status
4. If it fails, sleeps 5 seconds and retries
5. When RCON succeeds, exits the loop (server is ready)

---

## Environment Variable Patterns

### Variable Substitution in Startup Command

```bash
# Template in egg
"startup": "proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe {{SERVER_MAP}}?listen?Port={{SERVER_PORT}}?RCONPort={{RCON_PORT}}?ServerAdminPassword=\"{{ARK_ADMIN_PASSWORD}}\""

# Conversion in entrypoint
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
# Result: proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe ${SERVER_MAP}?listen?Port=${SERVER_PORT}...

# Execution
eval ${MODIFIED_STARTUP}
# Expands all variables
```

**Pattern:** `{{VARIABLE}}` -> `${VARIABLE}` -> expanded by eval

### ARK Server Parameters

```bash
# Basic start parameters
TheIsland_WP?listen?Port=7777?QueryPort=27015?RCONPort=37015?RCONEnabled=True

# With password and max players
?ServerPassword=\"mypassword\"?MaxPlayers=70?ServerAdminPassword=\"adminpass\"

# PvE mode
?ServerPVE=True

# With mods
-mods=123456,654321,789012

# No BattlEye
-NoBattlEye
```

### SteamCMD Command Patterns

```bash
# Basic game install
+app_update 2430930 validate +quit

# Install with beta branch
+app_update 2430930 -beta "betaname" -betapassword "password" +quit

# Install multiple apps
+app_update 1007 +app_update 2430930 +quit

# Force Windows platform
+@sSteamCmdForcePlatformType windows +app_update 2430930 +quit

# Custom installation directory
+force_install_dir /custom/path +app_update 2430930 +quit

# With authentication
+login username password +app_update 2430930 +quit

# Anonymous login (no credentials)
+login anonymous +app_update 2430930 +quit
```

---

## Directory Structure

### After Installation Complete

```
/home/container/
├── .steam/
│   ├── steam/
│   │   ├── steamapps/
│   │   │   ├── compatdata/
│   │   │   │   └── 2430930/          # ARK SA App ID
│   │   │   │       └── pfx/          # Wine prefix
│   │   │   │           ├── drive_c/
│   │   │   │           ├── dosdevices/
│   │   │   │           └── ...
│   │   │   └── ...
│   │   └── ...
│   ├── sdk32/                         # 32-bit Steam client libraries
│   │   └── steamclient.so
│   └── sdk64/                         # 64-bit Steam client libraries
│       └── steamclient.so
├── steamcmd/
│   ├── steamcmd.sh
│   ├── linux32/
│   │   ├── steamclient.so            # Original 32-bit
│   │   └── ...
│   ├── linux64/
│   │   ├── steamclient.so            # Original 64-bit
│   │   └── ...
│   └── steamapps/
│       └── (game files during download)
└── ShooterGame/                       # ARK SA Installation
    ├── Binaries/
    │   └── Win64/
    │       ├── ArkAscendedServer.exe
    │       └── ...
    ├── Content/
    ├── Saved/
    │   ├── Config/
    │   │   └── WindowsServer/
    │   │       ├── GameUserSettings.ini
    │   │       ├── Game.ini
    │   │       └── ...
    │   ├── Logs/
    │   │   └── ShooterGame.log
    │   └── WorldData/
    └── ...
```

### Wine Prefix Structure (STEAM_COMPAT_DATA_PATH)

```
/home/container/.steam/steam/steamapps/compatdata/2430930/pfx/
├── drive_c/                    # Virtual C: drive
│   ├── Program Files/
│   ├── Program Files (x86)/
│   ├── Users/
│   │   └── steamuser/
│   │       └── AppData/
│   │           ├── Local/
│   │           └── Roaming/
│   └── Windows/
│       ├── System32/           # 64-bit Windows DLLs
│       ├── SysWOW64/           # 32-bit Windows DLLs
│       └── ...
├── dosdevices/
│   ├── c: -> drive_c           # Symbolic links to drives
│   └── ...
└── user.reg                    # Wine registry
```

---

## SteamCMD Command Patterns

### Standard ARK SA Installation

```bash
./steamcmd.sh \
    +force_install_dir /home/container \
    +login anonymous \
    +@sSteamCmdForcePlatformType windows \
    +app_update 1007 \
    +app_update 2430930 \
    validate \
    +quit
```

**What each line does:**
- `+force_install_dir`: Sets installation directory
- `+login anonymous`: Logs in without credentials
- `+@sSteamCmdForcePlatformType windows`: Forces Windows binary download
- `+app_update 1007`: Installs/updates Steam runtime
- `+app_update 2430930`: Installs/updates ARK SA
- `validate`: Verifies all files after download
- `+quit`: Exits SteamCMD

### With Authentication

```bash
./steamcmd.sh \
    +force_install_dir /home/container \
    +login username password \
    +app_update 2430930 \
    +quit
```

### With Beta Branch

```bash
./steamcmd.sh \
    +force_install_dir /home/container \
    +login anonymous \
    +app_update 2430930 \
    -beta "betabranch" \
    -betapassword "betapass" \
    +quit
```

---

## Summary

This reference document provides the complete code patterns used in Pelican Panel's working ARK SA implementation. The key takeaways are:

1. **Proton Setup**: Machine-ID reset, environment variables, compatdata directory
2. **Steam Runtime**: App ID 1007 is critical for providing dependencies
3. **Library Linking**: `.steam/sdk32` and `.steam/sdk64` must be populated
4. **Signal Handling**: Trap-based graceful shutdown with RCON integration
5. **Variable Patterns**: Conditional flags, parameter substitution, environment expansion
6. **Directory Structure**: Proper layout of Steam, Proton, and game files

All of these patterns can be adapted to other Windows games running through Proton on Linux containers.

