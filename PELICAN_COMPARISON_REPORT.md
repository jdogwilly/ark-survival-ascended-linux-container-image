# Pelican Panel ARK Survival Ascended Configuration - Detailed Comparison Report

**Date**: November 8, 2025
**Purpose**: Compare Pelican Panel's working ARK Ascended setup with our container to identify critical differences

---

## Executive Summary

Pelican Panel successfully runs ARK: Survival Ascended servers using the `ghcr.io/parkervcp/steamcmd:proton` Docker image. This report documents the exact configuration, startup approach, and key environmental differences that make Pelican's implementation work where ours currently fails.

---

## 1. Pelican Panel Docker Image: `ghcr.io/parkervcp/steamcmd:proton`

### 1.1 Base Configuration

**Dockerfile Analysis** (from `parkervcp/yolks/steamcmd/proton/Dockerfile`):

```dockerfile
FROM debian:bookworm-slim

# 32-bit architecture support
RUN dpkg --add-architecture i386

# Core packages installed:
- wget, iproute2, gnupg2, software-properties-common
- libntlm0, winbind, xvfb, xauth
- libncurses5-dev:i386, libncurses6
- dbus, libgdiplus, lib32gcc-s1
- alsa-tools, libpulse0, pulseaudio, libpulse-dev
- libasound2, libao-common
- gnutls-bin, gnupg, locales, cabextract
- curl, python3, python3-pip, python3-setuptools
- tini, file, pipx

# KEY DIFFERENCE #1: Downloads LATEST Proton-GE automatically
RUN curl -sLOJ "$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | egrep .tar.gz)"
RUN tar -xzf GE-Proton*.tar.gz -C /usr/local/bin/ --strip-components=1
RUN rm GE-Proton*.*

# KEY DIFFERENCE #2: Proton machine-id fix
RUN rm -f /etc/machine-id
RUN dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id
RUN dbus-uuidgen --ensure

# KEY DIFFERENCE #3: Protontricks installed
RUN pipx install protontricks

# KEY DIFFERENCE #4: Winetricks included
RUN wget -q -O /usr/sbin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x /usr/sbin/winetricks

# KEY DIFFERENCE #5: RCON CLI tool included
RUN cd /tmp/ \
    && curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz \
    && tar xvf rcon.tar.gz \
    && mv rcon-0.10.3-amd64_linux/rcon /usr/local/bin/

# User setup
RUN useradd -m -d /home/container -s /bin/bash container
USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

# Tini for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
```

### 1.2 Proton Version Differences

| Aspect | Pelican Panel | Our Container |
|--------|---------------|---------------|
| **Proton Version** | **LATEST** (auto-downloaded) | GE-Proton10-17 (pinned) |
| **Latest Available** | GE-Proton10-25 (Nov 2025) | GE-Proton10-17 (older) |
| **Installation Location** | `/usr/local/bin/` | `/home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/` |
| **Extraction Method** | Strip components, root install | Full path extraction |

**CRITICAL**: Pelican uses the LATEST Proton-GE release automatically. As of November 2025, this is **GE-Proton10-25**, which includes numerous fixes including:
- Fixed video playback in multiple games
- Updated Wine to latest bleeding edge
- Updated DXVK to latest git
- Updated VKD3D-Proton to latest git
- Fixed texture regressions
- Multiple game-specific protonfixes

---

## 2. Entrypoint Script Analysis

**Source**: `parkervcp/yolks/steamcmd/entrypoint.sh`

### 2.1 Environment Variable Setup

```bash
# KEY DIFFERENCE #6: Automatic Steam Compat Path Setup
if [ -f "/usr/local/bin/proton" ]; then
    if [ ! -z ${SRCDS_APPID} ]; then
        mkdir -p /home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/container/.steam/steam"
        export STEAM_COMPAT_DATA_PATH="/home/container/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"
        # Fix for pipx with protontricks
        export PATH=$PATH:/root/.local/bin
    else
        echo -e "WARNING!!! Proton needs variable SRCDS_APPID, else it will not work."
        exit 0
    fi
fi
```

**Our Implementation**:
```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/Steam
export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/steamapps/compatdata/2430930
```

**KEY DIFFERENCE**: Pelican creates the compat data path at `.steam/steam/steamapps/compatdata/` whereas we use `server-files/steamapps/compatdata/`. This may affect how Proton finds Steam libraries.

### 2.2 SteamCMD Auto-Update Logic

```bash
# KEY DIFFERENCE #7: Dual app_update commands
if [ "${STEAM_USER}" == "anonymous" ]; then
    ./steamcmd/steamcmd.sh +force_install_dir /home/container \
        +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
        $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
        +app_update 1007 \      # <-- Steam client libraries first!
        +app_update ${SRCDS_APPID} \
        $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) \
        $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) \
        $( [[ -z ${HLDS_GAME} ]] || printf %s "+app_set_config 90 mod ${HLDS_GAME}" ) \
        ${INSTALL_FLAGS} \
        $( [[ "${VALIDATE}" == "1" ]] && printf %s 'validate' ) \
        +quit
fi
```

**CRITICAL DISCOVERY**: Pelican runs `+app_update 1007` BEFORE the game server update. App 1007 is the **Steam Linux Runtime** / **Steam Client Libraries**. This ensures all Steam API dependencies are present.

**Our Implementation**: We only run `+app_update 2430930` (the game server), missing the Steam client libraries.

---

## 3. ARK Survival Ascended Egg Configuration

**Source**: `pelican-eggs/eggs/game_eggs/steamcmd_servers/ark_survival_ascended/egg-ark--survival-ascended.json`

### 3.1 Docker Image Specification

```json
{
  "docker_images": {
    "Proton": "ghcr.io/parkervcp/steamcmd:proton"
  }
}
```

### 3.2 Startup Command Structure

```bash
rmv() {
    echo "stopping server";
    rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} KeepAlive &&
    rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD} DoExit &&
    wait ${ARK_PID};
    echo "Server Closed";
    exit;
};

trap rmv 15 2;

proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
    {{SERVER_MAP}}?listen?MaxPlayers={{MAX_PLAYERS}}?SessionName=\"{{SESSION_NAME}}\" \
    ?Port={{SERVER_PORT}}?QueryPort={{QUERY_PORT}}?RCONPort={{RCON_PORT}}?RCONEnabled=True \
    $( [ "$SERVER_PVE" == "0" ] || printf %s '?ServerPVE=True' ) \
    ?ServerPassword="{{SERVER_PASSWORD}}"{{ARGS_PARAMS}} \
    ?ServerAdminPassword="{{ARK_ADMIN_PASSWORD}}" \
    -WinLiveMaxPlayers={{MAX_PLAYERS}} \
    -oldconsole -servergamelog \
    $( [ -z "$MOD_IDS" ] || printf %s ' -mods=' $MOD_IDS ) \
    $( [ "$BATTLE_EYE" == "1" ] || printf %s ' -NoBattlEye' ) \
    -Port={{SERVER_PORT}} {{ARGS_FLAGS}} &

ARK_PID=$! ;

tail -c0 -F ./ShooterGame/Saved/Logs/ShooterGame.log --pid=$ARK_PID &

until echo "waiting for rcon connection...";
    (rcon -t rcon -a 127.0.0.1:${RCON_PORT} -p ${ARK_ADMIN_PASSWORD})<&0 & wait $!;
do
    sleep 5;
done
```

### 3.3 Key Startup Differences

| Feature | Pelican Panel | Our Container |
|---------|---------------|---------------|
| **Proton Command** | `proton run` (simple) | `$STEAM_COMPAT_DIR/$PROTON_DIR_NAME/proton run` (full path) |
| **Signal Handling** | `trap rmv 15 2` with RCON shutdown | `trap graceful_shutdown SIGTERM SIGINT` |
| **RCON Tool** | Uses `rcon` CLI from gorcon | Uses custom `asa-ctrl rcon` |
| **Binary Path** | Relative: `./ShooterGame/Binaries/Win64/` | Relative: `./ShooterGame/Binaries/Win64/` (same) |
| **Working Directory** | `/home/container` (server-files root) | `/home/gameserver/server-files` (same) |
| **Background Process** | Uses `&` and `$!` for PID | Same approach |
| **Log Tailing** | `tail -c0 -F` with `--pid` | `tail -f` with `--pid` |

### 3.4 Environment Variables Used

```json
{
  "env_variable": "SRCDS_APPID",
  "default_value": "2430930"
}
```

**CRITICAL**: Pelican sets `SRCDS_APPID=2430930` which triggers the automatic Steam compat path setup in the entrypoint script.

---

## 4. Installation Script Differences

**Pelican's Installation Script**:
```bash
# Standard SteamCMD installation script
cd /tmp
mkdir -p /mnt/server/steamcmd
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzvf steamcmd.tar.gz -C /mnt/server/steamcmd
mkdir -p /mnt/server/steamapps # Fix steamcmd disk write error
cd /mnt/server/steamcmd

chown -R root:root /mnt
export HOME=/mnt/server

./steamcmd.sh +force_install_dir /mnt/server \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    +@sSteamCmdForcePlatformType windows \
    +app_update ${SRCDS_APPID} validate +quit

# KEY DIFFERENCE #8: Copy Steam client libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so ../.steam/sdk32/steamclient.so

mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so ../.steam/sdk64/steamclient.so

# Cleanup movies to save space
rm -rf /mnt/server/ShooterGame/Content/Movies

# Touch log file
mkdir -p /mnt/server/ShooterGame/Saved/Logs
echo "--fresh install--" >> /mnt/server/ShooterGame/Saved/Logs/ShooterGame.log
```

**CRITICAL DISCOVERY**: Pelican explicitly copies `steamclient.so` to `.steam/sdk32` and `.steam/sdk64` directories. This provides the Steam API libraries that ARK needs.

---

## 5. Critical Differences Summary

### 5.1 Missing Components in Our Container

1. **Steam Client Libraries (App 1007)**: Not installed
2. **steamclient.so stubs**: Not copied to `.steam/sdk32/` and `.steam/sdk64/`
3. **Proton Version**: Using older GE-Proton10-17 instead of latest (10-25)
4. **Proton Installation**: Full path vs. stripped components in `/usr/local/bin/`
5. **Steam Compat Paths**: Different directory structure
6. **machine-id**: Static vs. dynamically generated with dbus-uuidgen
7. **Protontricks**: Not installed (may not be critical)
8. **Winetricks**: Not installed (may not be critical)

### 5.2 Directory Structure Comparison

**Pelican Panel**:
```
/home/container/
├── .steam/
│   ├── sdk32/steamclient.so
│   ├── sdk64/steamclient.so
│   └── steam/
│       └── steamapps/
│           └── compatdata/
│               └── 2430930/
│                   └── pfx/ (Wine prefix)
├── steamcmd/
├── steamapps/ (game files)
└── ShooterGame/
```

**Our Container**:
```
/home/gameserver/
├── Steam/
│   └── compatibilitytools.d/
│       └── GE-Proton10-17/
├── steamcmd/
└── server-files/
    ├── steamapps/
    │   └── compatdata/
    │       └── 2430930/
    │           └── pfx/
    └── ShooterGame/
```

---

## 6. Recommended Changes to Our Container

### 6.1 HIGH PRIORITY (Likely Critical)

1. **Install Steam Client Libraries (App 1007)**
   ```bash
   # In start_server, after server files download:
   cd /home/gameserver/steamcmd
   ./steamcmd.sh +force_install_dir /home/gameserver/Steam \
       +login anonymous +app_update 1007 +quit
   ```

2. **Copy steamclient.so Stubs**
   ```bash
   # After SteamCMD installation:
   mkdir -p /home/gameserver/server-files/.steam/sdk32
   mkdir -p /home/gameserver/server-files/.steam/sdk64
   cp /home/gameserver/steamcmd/linux32/steamclient.so \
       /home/gameserver/server-files/.steam/sdk32/steamclient.so
   cp /home/gameserver/steamcmd/linux64/steamclient.so \
       /home/gameserver/server-files/.steam/sdk64/steamclient.so
   ```

3. **Update Steam Compat Paths**
   ```bash
   # Change from:
   export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/Steam
   export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/steamapps/compatdata/2430930

   # To:
   export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/server-files/.steam/steam
   export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/.steam/steam/steamapps/compatdata/2430930

   # And create symlink:
   mkdir -p /home/gameserver/server-files/.steam/steam
   ln -s /home/gameserver/server-files/steamapps \
       /home/gameserver/server-files/.steam/steam/steamapps
   ```

4. **Update Proton Version to Latest**
   ```bash
   # Change PROTON_VERSION from "10-17" to auto-detect latest:
   PROTON_VERSION=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep tag_name | cut -d'"' -f4 | sed 's/GE-Proton//')
   ```

### 6.2 MEDIUM PRIORITY (May Help Stability)

5. **Improve machine-id Generation**
   ```bash
   # In Dockerfile, replace static machine-id with dbus approach:
   RUN apt-get install -y dbus && \
       rm -f /etc/machine-id && \
       dbus-uuidgen --ensure=/etc/machine-id
   ```

6. **Add Tini for Signal Handling**
   ```dockerfile
   # In Dockerfile:
   RUN apt-get install -y tini
   ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
   CMD ["/usr/bin/start_server"]
   ```

7. **Set SRCDS_APPID Environment Variable**
   ```bash
   # In docker-compose.yml or Dockerfile:
   environment:
     - SRCDS_APPID=2430930
   ```

### 6.3 LOW PRIORITY (Optional Enhancements)

8. **Install Winetricks** (for debugging/manual fixes)
9. **Install Protontricks** (for advanced troubleshooting)
10. **Install gorcon/rcon CLI** (alternative RCON tool)

---

## 7. Testing Strategy

### 7.1 Incremental Testing Approach

**Test 1: Steam Client Libraries Only**
- Add App 1007 download
- Add steamclient.so copy
- Test if server launches

**Test 2: Steam Compat Path Changes**
- Update environment variables
- Create symlink structure
- Test if server launches

**Test 3: Proton Version Update**
- Update to GE-Proton10-25
- Test compatibility

**Test 4: Combined Changes**
- Apply all HIGH PRIORITY changes
- Test full startup sequence

### 7.2 Validation Checklist

After each test:
- [ ] Server process starts and stays running
- [ ] No "Steam must be running" errors
- [ ] No silent crashes
- [ ] RCON becomes available
- [ ] Server log file is created and updated
- [ ] Server accepts player connections

---

## 8. Known Issues from Pelican Community

### 8.1 Reported Problems

1. **Console Output Issues**: Some users reported console not showing properly after switching Proton versions. Fixed by recreating server instance.

2. **Proton_8 vs Latest**: Some users had success specifically with `ghcr.io/parkervcp/steamcmd:proton_8` tag instead of `:proton` (latest).

3. **BattlEye Compatibility**: Anti-cheat can be problematic in containers. Most Pelican setups run with `-NoBattlEye` flag.

### 8.2 Working Configurations

Based on community reports:
- **Docker Image**: `ghcr.io/parkervcp/steamcmd:proton` or `ghcr.io/parkervcp/steamcmd:proton_8`
- **Proton Version**: GE-Proton 8.x - 10.x (various versions reported working)
- **Required Flags**: `-oldconsole -servergamelog -NoBattlEye`
- **RCON**: Must be enabled for proper shutdown handling

---

## 9. Hypothesis on Why Pelican Works

### 9.1 The Most Likely Cause of Our Failure

**Steam API Initialization Failure**: Our container lacks the Steam client libraries (App 1007) and steamclient.so stubs. When ARK tries to initialize the Steam API:

1. It looks for `steamclient.so` in `.steam/sdk64/`
2. Doesn't find it (we don't copy it)
3. Tries to initialize Steam API anyway
4. Fails silently because there's no Steam client
5. Process exits with code 0 (no error detected)

**Evidence Supporting This**:
- Pelican explicitly copies steamclient.so to `.steam/sdk32/` and `.steam/sdk64/`
- Pelican downloads App 1007 (Steam client libraries) before the game server
- Our troubleshooting report mentions fixing steam_appid.txt but not Steam client libraries
- ARK dedicated servers on Windows require Steam to be installed, even though they're "dedicated servers"

### 9.2 Secondary Contributing Factors

1. **Proton Version**: GE-Proton10-25 may have ARK-specific fixes that 10-17 lacks
2. **Steam Compat Paths**: The path structure matters for Steam API discovery
3. **Environment Variables**: SRCDS_APPID may trigger additional Proton initialization

---

## 10. Recommended Immediate Actions

### 10.1 Quick Test (5 minutes)

Add to `start_server` after STAGE 4 (Server Files Download):

```bash
# STAGE 4.1: Steam Client Libraries Installation
log_stage "4.1" "Steam Client Libraries Installation"
log_info "Installing Steam Linux Runtime (App 1007) for Steam API support..."

cd /home/gameserver/steamcmd
./steamcmd.sh +force_install_dir /home/gameserver/server-files +login anonymous +app_update 1007 +quit

# Copy steamclient.so to expected locations
log_info "Copying Steam client libraries..."
mkdir -p /home/gameserver/server-files/.steam/sdk32
mkdir -p /home/gameserver/server-files/.steam/sdk64
cp -v /home/gameserver/steamcmd/linux32/steamclient.so /home/gameserver/server-files/.steam/sdk32/
cp -v /home/gameserver/steamcmd/linux64/steamclient.so /home/gameserver/server-files/.steam/sdk64/

log_success "Steam client libraries installed"
```

**Prediction**: This change alone has a HIGH probability of fixing the silent crash issue.

### 10.2 If Quick Test Succeeds

Document the fix and consider:
1. Updating Proton to latest version
2. Cleaning up unnecessary workarounds from troubleshooting
3. Adding tests to prevent regression

### 10.3 If Quick Test Fails

Move to Test 2 (Steam Compat Path changes) and Test 3 (Proton version update).

---

## 11. References

### 11.1 Source Files Analyzed

1. `parkervcp/yolks/steamcmd/proton/Dockerfile`
2. `parkervcp/yolks/steamcmd/entrypoint.sh`
3. `pelican-eggs/eggs/game_eggs/steamcmd_servers/ark_survival_ascended/egg-ark--survival-ascended.json`
4. GloriousEggroll/proton-ge-custom releases (GE-Proton10-17 through 10-25)

### 11.2 Key Resources

- Pelican Eggs Repository: https://github.com/pelican-eggs/games-steamcmd
- Parkervcp Yolks: https://github.com/parkervcp/yolks
- Proton-GE Releases: https://github.com/GloriousEggroll/proton-ge-custom/releases
- SteamCMD Wiki: https://developer.valvesoftware.com/wiki/SteamCMD

---

## 12. Conclusion

The most critical difference between Pelican's working setup and our container is the **presence of Steam client libraries (App 1007) and steamclient.so stubs**. Pelican explicitly installs these during the installation phase and copies the client libraries to expected locations.

Our container currently:
- ❌ Does NOT install App 1007
- ❌ Does NOT copy steamclient.so to `.steam/sdk32/` and `.steam/sdk64/`
- ❌ Uses an older Proton version (10-17 vs 10-25)
- ✅ Has correct directory structure
- ✅ Has correct startup parameters
- ✅ Has proper Wine prefix initialization

**Recommended First Step**: Implement the Steam client libraries installation (Test 1) as this has the highest probability of resolving the silent crash issue.

**Expected Outcome**: Server should launch successfully and remain running, allowing RCON connections and player access.

---

**Report Generated**: November 8, 2025
**Status**: Ready for Implementation Testing
