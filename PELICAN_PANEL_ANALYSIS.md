# Pelican Panel ARK Survival Ascended - Detailed Technical Analysis

**Author**: Claude Code Analysis
**Date**: November 8, 2025
**Purpose**: Comprehensive analysis of Pelican Panel's working ARK SA implementation vs our container

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Key Differences Overview](#key-differences-overview)
3. [Dockerfile Analysis](#dockerfile-analysis)
4. [Steam Client Components](#steam-client-components)
5. [Proton Configuration](#proton-configuration)
6. [Entrypoint Script Details](#entrypoint-script-details)
7. [Egg Configuration](#egg-configuration)
8. [Critical Installation Steps](#critical-installation-steps)
9. [Environment Variables](#environment-variables)
10. [Startup Command Structure](#startup-command-structure)
11. [RCON Integration](#rcon-integration)
12. [Key Insights & Differences](#key-insights--differences)

---

## Executive Summary

Pelican Panel successfully runs ARK: Survival Ascended servers using the `ghcr.io/parkervcp/steamcmd:proton` Docker image. Their implementation differs from ours in several critical ways:

1. **Dynamic Proton Version**: Uses latest Proton-GE (auto-downloaded) vs our pinned GE-Proton10-17
2. **Steam Client Installation**: Includes App ID 1007 installation during startup
3. **Proper Signal Handling**: Uses `tini` for PID 1 process management
4. **Machine-ID Fix**: Resets Proton machine-id on each container build
5. **Streamlined User**: Single `container` user (UID 1000) vs our `gameserver` (UID 25000)
6. **Integrated RCON**: Pre-installs `rcon-cli` tool for server management

---

## Key Differences Overview

| Feature | Pelican Panel | Our Container |
|---------|---------------|---------------|
| **Base Image** | `debian:bookworm-slim` | `ubuntu:24.04` |
| **User** | `container` (UID 1000) | `gameserver` (UID 25000) |
| **Proton Version** | Latest (auto-updated) | GE-Proton10-17 (pinned) |
| **Process Init** | tini | bash directly |
| **Installation Script** | Embedded in entrypoint | Separate start_server script |
| **Config Import** | Manual via variables | STAGE 4.5 auto-import from /config |
| **RCON Tool** | rcon-cli (v0.10.3) | Custom Python RCON implementation |
| **Python Tooling** | Python3 + pipx + protontricks | Zero-dependency Python package |

---

## Dockerfile Analysis

### Pelican's `ghcr.io/parkervcp/steamcmd:proton` Dockerfile

```dockerfile
FROM debian:bookworm-slim

LABEL author="Torsten Widmann" maintainer="info@goover.de"

# Enable 32-bit architecture support
RUN dpkg --add-architecture i386

# Install required system packages
RUN apt update && apt install -y --no-install-recommends \
    wget iproute2 gnupg2 software-properties-common \
    libntlm0 winbind xvfb xauth \
    libncurses5-dev:i386 libncurses6 dbus libgdiplus lib32gcc-s1 \
    alsa-tools libpulse0 pulseaudio libpulse-dev \
    libasound2 libao-common gnutls-bin gnupg locales \
    cabextract curl python3 python3-pip python3-setuptools \
    tini file pipx

# Download and extract latest Proton-GE
RUN curl -sLOJ "$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | \
    grep browser_download_url | cut -d\" -f4 | egrep .tar.gz)"
RUN tar -xzf GE-Proton*.tar.gz -C /usr/local/bin/ --strip-components=1
RUN rm GE-Proton*.*

# Fix Proton machine-id (critical for Proton compatibility)
RUN rm -f /etc/machine-id
RUN dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id
RUN dbus-uuidgen --ensure

# Install protontricks for advanced Proton management
RUN pipx install protontricks

# Install winetricks for Wine component management
RUN wget -q -O /usr/sbin/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
    chmod +x /usr/sbin/winetricks

# Install RCON CLI tool for server management
RUN cd /tmp/ && \
    curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz && \
    tar xvf rcon.tar.gz && \
    mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/

# Setup user and working directory
RUN useradd -m -d /home/container -s /bin/bash container
USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

# Use tini as PID 1 for proper signal handling
STOPSIGNAL SIGINT
COPY --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
```

### Key Dockerfile Differences from Our Implementation

**1. Base Image Choice**
- Pelican uses `debian:bookworm-slim` (cleaner, smaller)
- We use `ubuntu:24.04` (heavier but more batteries-included)

**2. Proton Installation Strategy**
```bash
# Pelican: Extracts directly to /usr/local/bin/
RUN curl -sLOJ "$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest ...)"
RUN tar -xzf GE-Proton*.tar.gz -C /usr/local/bin/ --strip-components=1

# Our approach: Extracts to /home/gameserver/Steam/compatibilitytools.d/
# This means Proton must be in a specific location for Steam to find it
```

**3. Machine-ID Reset (CRITICAL for Proton)**
```bash
RUN rm -f /etc/machine-id
RUN dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id
RUN dbus-uuidgen --ensure
```

This is critical because:
- Proton caches configurations based on machine-id
- A stale machine-id from another container can cause conflicts
- Each container gets a fresh UUID generation

**4. Signal Handling with tini**
```dockerfile
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
```

This is crucial because:
- tini acts as PID 1 and properly forwards signals
- Enables graceful shutdown of child processes
- Prevents zombie processes
- Our direct bash approach doesn't handle this well

---

## Steam Client Components

### Critical: App ID 1007 Installation

The entrypoint script includes this crucial line:

```bash
./steamcmd/steamcmd.sh +force_install_dir /home/container \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    +app_update 1007 \
    +app_update ${SRCDS_APPID} \
    ...
```

**What is App ID 1007?**

App ID 1007 is the **Steam Proton runtime bootstrap** - it installs:
- Steam Runtime components needed for Proton
- 32-bit Steam client libraries (`linux32/steamclient.so`)
- 64-bit Steam client libraries (`linux64/steamclient.so`)
- Core compatibility layer files

**Why it matters:**
- Proton requires these libraries to function
- Without it, Proton cannot establish the compatibility layer
- This is automatically downloaded during the first update

### steamclient.so Installation

The installation script explicitly handles this:

```bash
# Set up 32-bit libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

# Set up 64-bit libraries
mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so
```

These files are:
- Downloaded by SteamCMD as part of the installation
- Copied to the `.steam/sdk32` and `.steam/sdk64` directories
- Essential for Wine/Proton's DLL loading mechanism
- Architecture-specific (32-bit and 64-bit versions)

---

## Proton Configuration

### Environment Variables Setup

The Pelican entrypoint sets these crucial variables when Proton is detected:

```bash
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}

        # Set Steam compatibility paths
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"

        # Fix for pipx with protontricks
        export PATH=$PATH:/root/.local/bin
    else
        echo "WARNING!!! Proton needs variable SRCDS_APPID"
        exit 0
    fi
fi
```

**Key points:**

1. **STEAM_COMPAT_CLIENT_INSTALL_PATH**: Tells Proton where Steam is installed (for library finding)
2. **STEAM_COMPAT_DATA_PATH**: Per-game prefix location for Windows environment
3. **`compatdata/${SRCDS_APPID}`**: Directory structure that Proton expects
4. **PATH extension**: Makes protontricks available (if used)

### Version Differences

**Pelican's Latest Proton (as of Nov 2025): GE-Proton10-25**

This version includes:
- Updated Wine to latest bleeding edge
- Updated DXVK to latest git
- Updated VKD3D-Proton to latest git
- Numerous game-specific ProtonFixes
- Better anti-cheat support (BattlEye, EasyAntiCheat)

**Our Version: GE-Proton10-17**

This is older and missing recent fixes:
- Missing ProtonFixes for ARK SA
- Older DXVK (may have rendering issues)
- Older Wine (may have stability issues)

---

## Entrypoint Script Details

### Pelican's Entrypoint Structure

```bash
#!/bin/bash

# 1. Initialize container environment
sleep 1

# Set timezone and internal IP
TZ=${TZ:-UTC}
export TZ
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# 2. Setup Proton environment if present
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        export PATH=$PATH:/root/.local/bin
    fi
fi

# 3. Change to working directory
cd /home/container || exit 1

# 4. Setup Steam user
if [ "${STEAM_USER}" == "" ]; then
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
fi

# 5. Auto-update game server
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        ./steamcmd/steamcmd.sh \
            +force_install_dir /home/container \
            +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
            $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
            +app_update 1007 \
            +app_update ${SRCDS_APPID} \
            ... validate +quit
    fi
fi

# 6. Execute startup command
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"
eval ${MODIFIED_STARTUP}
```

### Critical Differences from Our Approach

**Our Approach (start_server script):**
- Much longer and more complex
- Handles individual validation steps
- Attempts ProtonFixes configuration
- Imports config files (STAGE 4.5)
- Creates symlinks for compatibility

**Pelican's Approach:**
- Minimal, streamlined entrypoint
- Delegates to SteamCMD for updates
- Relies on Proton's default configuration
- Uses environment variables exclusively
- Single unified startup process

---

## Egg Configuration

### ARK: Survival Ascended Egg Variables

From `egg-ark--survival-ascended.json`:

```json
{
    "docker_images": {
        "Proton": "ghcr.io/parkervcp/steamcmd:proton"
    },
    "startup": "rmv() { ... }; trap rmv 15 2; proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe ...",
    "variables": [
        {
            "name": "Server Map",
            "env_variable": "SERVER_MAP",
            "default_value": "TheIsland_WP"
        },
        {
            "name": "Max Players",
            "env_variable": "MAX_PLAYERS",
            "default_value": "70"
        },
        // ... additional variables
    ]
}
```

### Installation Script

The egg includes a standardized installation script:

```bash
#!/bin/bash

# Variables setup
if [[ "${STEAM_USER}" == "" ]] || [[ "${STEAM_PASS}" == "" ]]; then
    STEAM_USER=anonymous
    STEAM_PASS=""
    STEAM_AUTH=""
fi

# Download and extract SteamCMD
cd /tmp
mkdir -p /mnt/server/steamcmd
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
mkdir -p /mnt/server/steamapps
cd /mnt/server/steamcmd

# Set ownership
chown -R root:root /mnt
export HOME=/mnt/server

# Install using SteamCMD
./steamcmd.sh \
    +force_install_dir /mnt/server \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    +@sSteamCmdForcePlatformType windows \
    +app_update ${SRCDS_APPID} \
    validate +quit

# Setup Steam client libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so

# Cleanup
rm -rf /mnt/server/ShooterGame/Content/Movies

# Touch log file
mkdir -p /mnt/server/ShooterGame/Saved/Logs
echo "--fresh install--" >> /mnt/server/ShooterGame/Saved/Logs/ShooterGame.log
```

---

## Critical Installation Steps

### Step-by-Step: What Happens During Installation

**1. SteamCMD Download**
```bash
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
```

**2. Steam Runtime Bootstrap (App ID 1007)**
```bash
./steamcmd.sh +app_update 1007 +quit
```
- Downloads Steam runtime components
- Installs `linux32/steamclient.so` and `linux64/steamclient.so`
- Extracts to `steamcmd/` directory

**3. Application Download (App ID 2430930 for ARK SA)**
```bash
./steamcmd.sh +@sSteamCmdForcePlatformType windows +app_update 2430930 validate +quit
```
- Downloads Windows game binaries
- Validates checksums
- Installs to `/mnt/server/ShooterGame/`

**4. Steam Client Library Linking**
```bash
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so
```

This critical step:
- Makes Steam client libraries available to Wine
- Enables 32-bit and 64-bit library loading
- These are extracted from the steamcmd directory itself

**5. Directory Structure After Installation**
```
/mnt/server/
├── .steam/
│   ├── sdk32/
│   │   └── steamclient.so (32-bit)
│   └── sdk64/
│       └── steamclient.so (64-bit)
├── steamcmd/
│   ├── steamcmd.sh
│   ├── linux32/
│   │   └── steamclient.so (original)
│   ├── linux64/
│   │   └── steamclient.so (original)
│   └── ...
├── steamapps/
│   └── compatdata/
│       └── 2430930/
│           └── pfx/ (Wine prefix)
└── ShooterGame/
    └── Binaries/Win64/ArkAscendedServer.exe
```

---

## Environment Variables

### Required Environment Variables for ARK SA

| Variable | Default | Purpose |
|----------|---------|---------|
| `SRCDS_APPID` | `2430930` | ARK SA App ID (Windows) |
| `SERVER_MAP` | `TheIsland_WP` | Starting map name |
| `SESSION_NAME` | `A Pterodactyl Hosted Server` | Server display name |
| `MAX_PLAYERS` | `70` | Maximum concurrent players |
| `RCON_PORT` | `37015` | RCON command port |
| `SERVER_PORT` | `7777` | Game server port |
| `QUERY_PORT` | `27015` | Steam server browser port |
| `ARK_ADMIN_PASSWORD` | (required) | Admin/RCON password |
| `SERVER_PASSWORD` | `` | Server join password (optional) |
| `BATTLE_EYE` | `1` | Enable BattlEye anti-cheat |
| `SERVER_PVE` | `1` | Enable PvE mode |
| `AUTO_UPDATE` | `1` | Auto-update on restart |
| `MOD_IDS` | `` | CurseForge mod IDs (comma-separated) |

### Proton-Specific Variables (Set by Entrypoint)

```bash
STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/2430930"
```

### Our Missing Variables

Our container doesn't explicitly set these, which may cause issues:
- `STEAM_COMPAT_CLIENT_INSTALL_PATH`
- `STEAM_COMPAT_DATA_PATH`
- Proper `HOME` directory for Proton

---

## Startup Command Structure

### Pelican's Startup Command (from egg)

```bash
rmv() {
    echo "stopping server";
    rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} KeepAlive && \
    rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} DoExit && \
    wait ${ARK_PID};
    echo "Server Closed";
    exit;
};
trap rmv 15 2;

proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
    {{SERVER_MAP}}?listen?MaxPlayers={{MAX_PLAYERS}}?SessionName=\"{{SESSION_NAME}}\"?Port={{SERVER_PORT}}?QueryPort={{QUERY_PORT}}?RCONPort={{RCON_PORT}}?RCONEnabled=True$( [  "$SERVER_PVE" == "0" ] || printf %s '?ServerPVE=True' )?ServerPassword=\"{{SERVER_PASSWORD}}\"{{ARGS_PARAMS}}?ServerAdminPassword=\"{{ARK_ADMIN_PASSWORD}}\" \
    -WinLiveMaxPlayers={{MAX_PLAYERS}} \
    -oldconsole \
    -servergamelog$( [ -z "$MOD_IDS" ] || printf %s ' -mods=' $MOD_IDS )$( [ "$BATTLE_EYE" == "1" ] || printf %s ' -NoBattlEye' ) \
    -Port={{SERVER_PORT}} \
    {{ARGS_FLAGS}} &

ARK_PID=$! ;

tail -c0 -F ./ShooterGame/Saved/Logs/ShooterGame.log --pid=$ARK_PID &

until echo "waiting for rcon connection..."; (rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD})<&0 & wait $!; do sleep 5; done
```

### Key Components Explained

**1. Signal Handler Function**
```bash
rmv() {
    echo "stopping server";
    rcon ... KeepAlive && rcon ... DoExit && wait ${ARK_PID};
    echo "Server Closed";
    exit;
}
```
- Defines graceful shutdown handler
- Sends RCON commands to save world and exit
- Waits for process to finish

**2. Trap Setup**
```bash
trap rmv 15 2
```
- Catches SIGTERM (15) and SIGINT (2)
- Executes graceful shutdown instead of hard kill

**3. Proton Launch**
```bash
proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
    [parameters...] &
ARK_PID=$!
```
- Uses Proton to run Windows executable
- Launches in background
- Captures process ID for monitoring

**4. Log Monitoring**
```bash
tail -c0 -F ./ShooterGame/Saved/Logs/ShooterGame.log --pid=$ARK_PID &
```
- Streams logs from the moment they're written
- Follows the server process (--pid)
- Runs in background

**5. Readiness Check**
```bash
until echo "waiting for rcon connection...";
    (rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD})<&0 &
    wait $!;
do sleep 5; done
```
- Repeatedly tries to connect via RCON
- Waits 5 seconds between attempts
- Continues until RCON responds (server ready)

### Our Approach Differences

Our `start_server` script:
- Uses `exec` to replace shell process (tricky signal handling)
- Doesn't use Proton directly (`proton run`)
- Missing proper RCON integration
- No readiness check mechanism

---

## RCON Integration

### Pelican's RCON Tool: `rcon-cli`

**Installation:**
```dockerfile
RUN cd /tmp/ && \
    curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz && \
    tar xvf rcon.tar.gz && \
    mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/
```

**Usage:**
```bash
# Basic command
rcon -t rcon -a 127.0.0.1:37015 -p password "command"

# Examples in startup
rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} KeepAlive
rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} DoExit
```

**Advantages:**
- Battle-tested tool (gorcon/rcon-cli)
- Built-in support for various RCON protocols
- Used in production by Pterodactyl
- Enables readiness checks via RCON connectivity

### Our Python RCON Implementation

**Location:** `/usr/share/asa-ctrl/asa_ctrl/rcon.py`

**Advantages:**
- Zero external dependencies
- Part of our unified control tool
- More flexibility for custom commands

**Disadvantages:**
- Custom implementation (less battle-tested)
- Requires proper configuration discovery
- More complex integration needed

---

## Key Insights & Differences

### 1. Proton Version Strategy

**Pelican (Dynamic):**
- Downloads latest Proton-GE at image build time
- Gets updated with each image rebuild
- Currently: GE-Proton10-25 (Nov 2025)

**Us (Pinned):**
- Uses GE-Proton10-17 (hardcoded)
- Only updates via code changes
- Missing recent fixes and improvements

**Recommendation:** Switch to dynamic versioning or upgrade to GE-Proton10-25

### 2. Machine-ID Reset

**Pelican:**
```bash
RUN rm -f /etc/machine-id && dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id && dbus-uuidgen --ensure
```

**Us:** No equivalent

**Why it matters:**
- Proton caches settings per machine-id
- A stale ID causes "unit test mode" issues
- Fresh ID enables proper initialization

### 3. Steam Client Libraries

**Critical Step We May Be Missing:**
```bash
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so
```

These libraries are:
- Downloaded as part of App ID 1007
- Essential for Proton to find Windows libraries
- Must be in `.steam/sdk32` and `.steam/sdk64` directories

### 4. Process Management

**Pelican:** Uses `tini` as PID 1
```dockerfile
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
```

**Us:** Direct bash execution

**Why it matters:**
- tini handles zombie processes
- Proper signal forwarding
- Graceful shutdown behavior

### 5. User Context

**Pelican:** Uses `container` (UID 1000)
**Us:** Uses `gameserver` (UID 25000)

**Impact:**
- Home directory: `/home/container` vs `/home/gameserver`
- Wine prefix: ~/.steam/steam vs /home/gameserver/.wine
- Permissions: Standard user vs custom UID

### 6. Proton Initialization

**Pelican Entrypoint:**
```bash
if [ -f "/usr/local/bin/proton" ]; then
    mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
    export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
fi
```

**Key point:** Explicitly creates the compatdata directory per-app

**Us:** Relies on Proton to create this automatically

### 7. SteamCMD Update Flow

**Pelican's Flow:**
1. Check if auto-update is enabled (default: yes)
2. Run SteamCMD with App ID 1007
3. Run SteamCMD with App ID 2430930 (ARK SA)
4. Validate checksums
5. Continue to startup

**Our Flow:**
1. Download/validate SteamCMD if missing
2. Install/update ASA via SteamCMD
3. Import user config files
4. Download/validate Proton
5. Initialize Proton prefix
6. Check for mods
7. Optionally install ASA API plugin
8. Launch server

Our flow is more complex but also more flexible.

### 8. Startup Command Difference

**Pelican:**
```bash
proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe [params] &
```

**Us:**
```bash
exec /home/gameserver/.steam/steam/compatibilitytools.d/GE-Proton10-17/proton run \
    /home/gameserver/server-files/ShooterGame/Binaries/Win64/ArkAscendedServer.exe [params]
```

**Why different:**
- Proton location (in PATH vs full path)
- Use of `exec` vs background (&)
- Path differences due to user/directory structure

### 9. Signal Handling & Graceful Shutdown

**Pelican:**
```bash
rmv() { rcon ... DoExit && wait ${ARK_PID}; }
trap rmv 15 2
```
- Sends in-game save/exit command
- Waits for process to exit cleanly
- Enables graceful shutdown

**Us:**
```bash
exec ... # Direct replacement
```
- Process gets SIGTERM directly
- May not save world properly
- Risk of data corruption

---

## Critical Implementation Items

### Must-Have Changes

1. **Machine-ID Reset**
   - Add to Dockerfile or entrypoint
   - Fixes "unit test mode" errors
   - Enables proper Proton initialization

2. **Steam Client Libraries**
   - Copy `linux32/steamclient.so` and `linux64/steamclient.so`
   - Create `.steam/sdk32` and `.steam/sdk64` directories
   - Essential for Proton compatibility

3. **App ID 1007 Installation**
   - Ensure SteamCMD installs this bootstrap
   - Provides Steam runtime components
   - Required for Proton to function

4. **Proton Environment Variables**
   - Set `STEAM_COMPAT_CLIENT_INSTALL_PATH`
   - Set `STEAM_COMPAT_DATA_PATH`
   - Create compatdata directory per-app

5. **Signal Handling**
   - Implement graceful shutdown via trap
   - Use RCON to send save/exit commands
   - Wait for process to exit cleanly

### Nice-to-Have Improvements

1. **Upgrade Proton Version**
   - Move from GE-Proton10-17 to GE-Proton10-25
   - Get recent game fixes and improvements
   - Better anti-cheat support

2. **Use tini for PID 1**
   - Add to base image
   - Enables proper signal handling
   - Prevents zombie processes

3. **Integrate rcon-cli**
   - Install gorcon/rcon-cli
   - Use for readiness checks
   - Enables graceful shutdown

4. **Simplify Entrypoint**
   - Current approach is complex but flexible
   - Could benefit from cleaner organization
   - Balance simplicity vs features

---

## Conclusion

Pelican Panel's ARK SA implementation works because:

1. **Proper Proton Setup**: Machine-ID reset, correct environment variables
2. **Steam Runtime**: App ID 1007 bootstrap ensures dependencies are available
3. **Stream Libraries**: Properly copied `.steam/sdk32` and `.steam/sdk64`
4. **Clean Process Management**: tini for signal handling, trap for graceful shutdown
5. **Battle-Tested Tools**: Uses proven components (rcon-cli, steamcmd)
6. **Minimal Complexity**: Streamlined entrypoint with environment variable flexibility

Our implementation can be fixed by:

1. Adding machine-ID reset to Dockerfile or entrypoint
2. Ensuring Steam client libraries are properly installed
3. Setting Proton environment variables correctly
4. Implementing graceful shutdown via trap and RCON
5. Consider upgrading Proton version
6. Optionally adopting tini for better signal handling

The most critical issue is likely the missing machine-ID reset and/or missing Steam client libraries, which would cause the "unit test mode" error and Proton initialization failures we're seeing.

---

## References

- **Pelican-Eggs Repository**: https://github.com/pelican-eggs/eggs
- **Parkervcp/Yolks**: https://github.com/parkervcp/yolks
- **Proton-GE Releases**: https://github.com/GloriousEggroll/proton-ge-custom
- **Gorcon RCON CLI**: https://github.com/gorcon/rcon-cli
- **Protontricks**: https://github.com/Winetricks/protontricks
- **SteamCMD Documentation**: https://developer.valvesoftware.com/wiki/SteamCMD

