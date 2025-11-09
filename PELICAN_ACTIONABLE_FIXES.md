# Pelican Panel Analysis - Actionable Fixes

**Purpose**: Translate Pelican Panel insights into concrete fixes for our ARK SA container

---

## Critical Issue Summary

Our container fails because it's missing 3-4 critical components that Pelican's implementation includes:

1. **Machine-ID Reset** - Causes "Proton unit test mode" errors
2. **Steam Client Libraries** - `.steam/sdk32` and `.steam/sdk64` are missing
3. **App ID 1007 Installation** - Steam runtime bootstrap not installed
4. **Proton Environment Variables** - Not explicitly set in entrypoint

---

## Fix #1: Add Machine-ID Reset to Dockerfile

**Current State**: Our Dockerfile doesn't reset machine-id
**Problem**: Proton caches configurations based on machine-id; stale IDs cause initialization failures
**Pelican's Solution**: Resets machine-id on each build

### Implementation

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/Dockerfile`

**Add after installing dbus (around line 40)**:

```dockerfile
# Fix Proton machine-id (prevents "unit test mode" errors)
RUN rm -f /etc/machine-id
RUN dbus-uuidgen --ensure=/etc/machine-id
RUN rm /var/lib/dbus/machine-id
RUN dbus-uuidgen --ensure
```

**Why this works:**
- Fresh machine-id forces Proton to reinitialize
- dbus-uuidgen generates unique IDs
- Prevents cached configuration conflicts

---

## Fix #2: Ensure Steam Client Libraries are Installed

**Current State**: We may not be copying `.steam/sdk32` and `.steam/sdk64` properly
**Problem**: Proton can't find Windows DLLs without these libraries
**Pelican's Solution**: Explicitly copies after SteamCMD download

### Implementation

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/root/usr/bin/start_server`

**Add after SteamCMD installation (around line 200-220)**:

```bash
# CRITICAL: Set up Steam client libraries for Proton
# These are downloaded by SteamCMD and must be symlinked

if [ -d "/home/gameserver/steamcmd/linux32" ]; then
    echo "[INFO] Setting up 32-bit Steam client library..."
    mkdir -p /home/gameserver/.steam/sdk32
    cp -v /home/gameserver/steamcmd/linux32/steamclient.so /home/gameserver/.steam/sdk32/steamclient.so 2>/dev/null || true
else
    echo "[WARNING] 32-bit steamclient.so not found in SteamCMD directory"
fi

if [ -d "/home/gameserver/steamcmd/linux64" ]; then
    echo "[INFO] Setting up 64-bit Steam client library..."
    mkdir -p /home/gameserver/.steam/sdk64
    cp -v /home/gameserver/steamcmd/linux64/steamclient.so /home/gameserver/.steam/sdk64/steamclient.so 2>/dev/null || true
else
    echo "[WARNING] 64-bit steamclient.so not found in SteamCMD directory"
fi

# Fix permissions
chmod 755 /home/gameserver/.steam/sdk32 /home/gameserver/.steam/sdk64 2>/dev/null || true
chmod 644 /home/gameserver/.steam/sdk32/steamclient.so /home/gameserver/.steam/sdk64/steamclient.so 2>/dev/null || true
```

**Why this works:**
- SteamCMD extracts these libraries during App ID 1007 installation
- Libraries must be in `.steam/sdk32` and `.steam/sdk64` for Proton to find them
- Proton uses these to load Windows DLLs through Wine

---

## Fix #3: Ensure App ID 1007 is Installed

**Current State**: Our SteamCMD installation may not include App ID 1007
**Problem**: App ID 1007 provides the Steam runtime bootstrap
**Pelican's Solution**: Explicitly adds `+app_update 1007` before game install

### Implementation

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/root/usr/bin/start_server`

**Find the SteamCMD update section and modify it**:

```bash
# Current (likely):
./steamcmd/steamcmd.sh +force_install_dir /home/gameserver \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
    +app_update 2430930 \
    validate +quit

# New (with App ID 1007):
./steamcmd/steamcmd.sh +force_install_dir /home/gameserver \
    +login ${STEAM_USER} ${STEAM_PASS} ${STEAM_AUTH} \
    $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
    +app_update 1007 \
    +app_update 2430930 \
    validate +quit
```

**Why this works:**
- App ID 1007 is the Steam Proton runtime bootstrap
- Provides essential compatibility layer files
- Must be installed before the game (App ID 2430930)
- This is what downloads the steamclient.so files

---

## Fix #4: Set Proton Environment Variables Explicitly

**Current State**: Environment variables may not be set properly for Proton
**Problem**: Proton can't find Steam or the Wine prefix without these
**Pelican's Solution**: Sets them explicitly in entrypoint

### Implementation

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/root/usr/bin/start_server`

**Add at the beginning of the script (after shebang and before main logic)**:

```bash
#!/bin/bash

# ... existing code ...

# Set up Proton environment variables (critical for compatibility)
export SRCDS_APPID=2430930  # ARK: Survival Ascended App ID
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/gameserver/.steam/steam"
export STEAM_COMPAT_DATA_PATH="/home/gameserver/.steam/steam/steamapps/compatdata/${SRCDS_APPID}"

# Create compatdata directory structure
mkdir -p /home/gameserver/.steam/steam/steamapps/compatdata/${SRCDS_APPID}

# Additional Proton environment fixes
export PROTONFIXES_CONFIG_DIR="/home/gameserver/.config/protonfixes"
mkdir -p "${PROTONFIXES_CONFIG_DIR}"

# Disable ProtonFixes unit test mode
export PROTONFIXES_DISABLE_PROTON_UNIT_TEST=0

# XDG runtime directory (needed for various Linux services)
export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
```

**Why this works:**
- `STEAM_COMPAT_CLIENT_INSTALL_PATH`: Tells Proton where Steam is (for library finding)
- `STEAM_COMPAT_DATA_PATH`: Tells Proton where to put the Wine prefix per-game
- compatdata directory structure is required by Proton
- Creates necessary directories before launching

---

## Fix #5: Optional - Upgrade Proton Version

**Current State**: Using GE-Proton10-17 (older)
**Benefit**: Get recent fixes and improvements
**Pelican's Solution**: Uses latest Proton-GE (auto-updated)

### Implementation Option A: Dynamic Version (Recommended)

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/Dockerfile`

**Replace the Proton download section** (around line 55-65):

```dockerfile
# Download latest Proton-GE dynamically (auto-updates on rebuild)
RUN curl -sLOJ "$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | \
    grep browser_download_url | cut -d\" -f4 | egrep .tar.gz)"
RUN tar -xzf GE-Proton*.tar.gz -C /usr/local/bin/ --strip-components=1
RUN rm GE-Proton*.*
```

**Advantages:**
- Always gets latest Proton version
- Updated on each image rebuild
- Automatic bug fixes and improvements

### Implementation Option B: Upgrade to Specific Version (Conservative)

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/root/usr/share/proton/`

**Update VERSION file and download latest sha512**:

```bash
# Update to GE-Proton10-25 (latest as of Nov 2025)
# Download: https://github.com/GloriousEggroll/proton-ge-custom/releases/download/10-25/GE-Proton10-25.tar.gz

# Then update the start_server script to use it
PROTON_VERSION="10-25"
```

**Advantages:**
- More control over which version to use
- Can test specific versions before deploying
- Conservative approach

---

## Fix #6: Optional - Add tini for Better Signal Handling

**Current State**: Using bash directly as PID 1
**Benefit**: Better signal forwarding, prevents zombie processes
**Pelican's Solution**: Uses tini

### Implementation

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/Dockerfile`

**Add package installation** (around line 25):

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    # ... existing packages ...
    tini \
    # ... rest of packages ...
```

**Then update docker-compose.yml** if needed:

```yaml
services:
  asa-server:
    image: ghcr.io/jdogwilly/asa-linux-server:latest
    # ... other config ...
    entrypoint: ["/usr/bin/tini", "-g", "--"]
    command: ["/usr/bin/start_server"]
```

**Why this works:**
- tini handles PID 1 properly
- Forwards signals to child processes
- Prevents zombie processes
- Enables graceful shutdown

---

## Fix #7: Optional - Implement Graceful Shutdown Handler

**Current State**: May not be handling shutdown gracefully
**Benefit**: Server saves world and data before exiting
**Pelican's Solution**: Uses trap with RCON commands

### Implementation

**File**: `/home/jacob/Repos/ark-survival-ascended-linux-container-image-troubleshoot-against-pelican/root/usr/bin/start_server`

**Add before launching the server**:

```bash
# Graceful shutdown handler
graceful_shutdown() {
    echo "[INFO] Received shutdown signal, saving world..."

    # Attempt RCON shutdown if ADMIN_PASSWORD is set
    if [ ! -z "${ARK_ADMIN_PASSWORD}" ]; then
        echo "[INFO] Sending RCON shutdown command..."
        /usr/local/bin/asa-ctrl rcon --exec "saveworld" 2>/dev/null || true
        sleep 2
        /usr/local/bin/asa-ctrl rcon --exec "doexit" 2>/dev/null || true
    fi

    echo "[INFO] Server Closed"
    exit 0
}

# Install signal handlers
trap graceful_shutdown SIGTERM SIGINT

# Launch server in background
exec /path/to/proton run /path/to/ArkAscendedServer.exe [params] &
ARK_PID=$!

# Wait for server process
wait ${ARK_PID}
```

**Why this works:**
- Saves world data before shutdown
- Allows graceful exit instead of hard kill
- Prevents data corruption

---

## Implementation Priority & Order

### Phase 1: Critical (Must Fix) - 30 min

These fixes are essential and must be applied:

1. **Machine-ID Reset** (5 min)
   - Add dbus-uuidgen calls to Dockerfile
   - Fixes "Proton unit test mode" errors

2. **Steam Client Libraries** (10 min)
   - Add `.steam/sdk32` and `.steam/sdk64` setup
   - Essential for Proton to function

3. **App ID 1007** (5 min)
   - Add `+app_update 1007` to SteamCMD commands
   - Provides Steam runtime dependencies

4. **Proton Environment Variables** (10 min)
   - Set `STEAM_COMPAT_*` variables
   - Create compatdata directory structure

### Phase 2: Important (Should Fix) - 20 min

These fixes improve reliability and debugging:

5. **XDG_RUNTIME_DIR** (5 min)
   - Ensure proper runtime directory setup
   - Fixes various Wine/Proton warnings

6. **ProtonFixes Config** (5 min)
   - Create `.config/protonfixes` directory
   - Allows ProtonFixes to save configuration

7. **Upgrade Proton Version** (10 min)
   - Upgrade to GE-Proton10-25
   - Get recent bug fixes

### Phase 3: Nice-to-Have (Should Consider) - 15 min

These fixes improve robustness:

8. **Add tini** (5 min)
   - Better signal handling as PID 1

9. **Graceful Shutdown Handler** (10 min)
   - Trap-based shutdown with RCON
   - Enables proper world saving

---

## Testing Checklist

After implementing fixes, verify each one:

### Test 1: Container Builds
```bash
docker build -t asa-test:latest .
# Should complete without errors
```

### Test 2: Container Starts
```bash
docker run --rm -it asa-test:latest /bin/bash
# Should start and give shell prompt
```

### Test 3: Proton Initializes
```bash
docker exec -it asa-server bash
env | grep -i proton
# Should show STEAM_COMPAT_* variables
```

### Test 4: Steam Client Libraries Exist
```bash
docker exec -it asa-server ls -la /home/gameserver/.steam/sdk32/
docker exec -it asa-server ls -la /home/gameserver/.steam/sdk64/
# Both should show steamclient.so
```

### Test 5: Server Starts (Not Crashes)
```bash
docker logs -f asa-server | head -100
# Should see initialization messages, not immediate crash
```

### Test 6: RCON Works
```bash
docker exec asa-server /usr/local/bin/asa-ctrl rcon --exec "help"
# Should execute RCON command successfully
```

---

## Expected Results After Fixes

### Before Fixes
```
Container starts → Server process exits in 2-10 seconds
Logs show: "ProtonFixes WARN: unit test mode"
Logs show: "wine: could not open working directory"
```

### After Phase 1 Fixes
```
Container starts → Server process runs longer
Logs show: Proton initialization messages
Logs show: Server loading game files
```

### After Phase 2 Fixes
```
Container starts → Server runs stably
Logs show: Clean startup without warnings
Logs show: Server ready for players
```

### After Phase 3 Fixes (Complete)
```
Container starts → Server runs stably
Shutdown sends RCON commands → World saved
Container stops gracefully
```

---

## Quick Implementation Guide

### Fastest Path (Phase 1 Only - 30 minutes)

1. Open Dockerfile, add machine-ID reset after dbus installation
2. Open start_server, add `.steam/sdk32/.steam/sdk64` setup
3. Open start_server, add `+app_update 1007` to SteamCMD
4. Open start_server, add STEAM_COMPAT_* environment variables
5. Build and test

### Complete Fix (All Phases - 1 hour)

1. Do all Phase 1 fixes
2. Add XDG_RUNTIME_DIR and ProtonFixes config setup
3. Upgrade Proton version
4. Add tini package and entrypoint
5. Implement graceful shutdown trap
6. Build and test thoroughly

---

## Common Issues After Implementation

### Issue: "Still getting unit test mode error"
**Solution**: Ensure machine-ID reset runs and Proton extracts fresh
```bash
docker image rm asa-linux-server:latest
docker build --no-cache -t asa-linux-server:latest .
```

### Issue: "steamclient.so not found"
**Solution**: Verify App ID 1007 installs successfully
```bash
docker logs asa-server | grep "app_update 1007"
# Should show successful download/install
```

### Issue: "Wine prefix not initializing"
**Solution**: Ensure compatdata directory is created
```bash
docker exec asa-server ls -la /home/gameserver/.steam/steam/steamapps/compatdata/2430930/
# Should exist and contain pfx directory
```

### Issue: "Server still crashes after fixes"
**Solution**: Check for other missing environment variables
```bash
docker exec asa-server env | grep -i steam
docker exec asa-server env | grep -i proton
# Verify all STEAM_COMPAT_* variables are set
```

---

## Conclusion

The 4 critical fixes (Machine-ID, Steam Libraries, App ID 1007, Proton Env Vars) address the root causes of our container failures. Implementing Phase 1 should resolve the immediate issues and get the server running.

Phase 2 and 3 improvements enhance reliability, ease of debugging, and operational robustness.

Follow the testing checklist after each phase to verify the fixes are working correctly.

