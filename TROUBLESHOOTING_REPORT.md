# ARK Survival Ascended Container Troubleshooting Report

**Date**: November 9, 2024
**Issue**: ARK server crashes immediately after launch in custom container but works in Pelican Panel

## Executive Summary

The ARK Survival Ascended dedicated server container experiences immediate crashes when launching through Wine/Proton. We've identified and fixed multiple infrastructure issues, but the game executable still exits silently after launch. The same server works correctly when hosted through Pelican Panel, suggesting a configuration or compatibility difference.

## Issues Identified and Fixed

### 1. ✅ Working Directory Management
**Problem**: Container was changing to `/home/gameserver/steamcmd` or binary directory
**Symptom**: `wine: could not open working directory L"unix\\home\\gameserver\\steamcmd\\"`
**Solution**: Set working directory to `/home/gameserver/server-files` before launch
**Status**: FIXED

### 2. ✅ Wine/Proton Path Mappings
**Problem**: Absolute paths not properly mapped in Wine
**Solution**:
- Use relative paths: `./ShooterGame/Binaries/Win64/ArkAscendedServer.exe`
- Create Z: drive mapping for cluster directory: `/cluster` → `Z:\cluster`
**Status**: FIXED

### 3. ✅ Missing steam_appid.txt
**Problem**: Steam API crashes without AppID file
**Symptom**: `FSteamServerInstanceHandler` crash in crash dumps
**Solution**: Create `/home/gameserver/server-files/steam_appid.txt` with content `2430930`
**Status**: FIXED

### 4. ✅ Missing 32-bit Dependencies
**Problem**: Wine/Proton requires 32-bit multimedia libraries
**Solution**: Added to Dockerfile:
```dockerfile
RUN dpkg --add-architecture i386
# Then installed:
- gstreamer1.0-plugins-* (base, good, bad, libav)
- libgstreamer* libraries
- libasound2:i386
- libpulse0:i386
- libgl1-mesa-dri:i386
- libsdl2-2.0-0:i386
```
**Status**: FIXED

### 5. ✅ XDG_RUNTIME_DIR Not Set
**Problem**: `XDG_RUNTIME_DIR is invalid or not set in the environment`
**Solution**: Create and set `XDG_RUNTIME_DIR=/tmp/runtime-gameserver`
**Status**: FIXED

### 6. ✅ ESYNC/FSYNC Compatibility
**Problem**: Synchronization methods can cause crashes in containers
**Solution**: Set `PROTON_NO_ESYNC=1` and `PROTON_NO_FSYNC=1`
**Status**: FIXED

### 7. ✅ Visual C++ Redistributables
**Problem**: Windows DLLs require vcredist
**Solution**: Download and install VC++ 2019 redistributables via Proton
**Status**: FIXED

### 8. ✅ Wine Prefix Not Initialized
**Problem**: Proton prefix needs explicit initialization
**Solution**: Run `wineboot --init` before first server launch
**Status**: FIXED

### 9. ✅ File Descriptor Limits
**Problem**: ARK requires 100,000+ open files
**Solution**: Added ulimits to docker-compose/run command
**Status**: FIXED

### 10. ✅ Environment Variable Expansion
**Problem**: ASA_START_PARAMS uses ${VAR} syntax
**Solution**: Use `envsubst` for expansion with debug logging
**Status**: FIXED

## Current Status

### What Works
- ✅ SteamCMD downloads and validates server files correctly
- ✅ Proton GE-10-17 installs and initializes
- ✅ Wine prefix creates successfully
- ✅ Visual C++ redistributables install
- ✅ steam_appid.txt is created
- ✅ All environment variables expand correctly
- ✅ Server binary launches without Wine path errors

### What Doesn't Work
- ❌ ARK server process exits immediately after launch (within 1-2 seconds)
- ❌ No error messages or crash dumps generated
- ❌ Process dies silently without logs

## Key Differences from Pelican

### Pelican Egg Configuration (from research)
```bash
# Pelican startup command structure:
proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
  {{SERVER_MAP}}?listen?MaxPlayers={{MAX_PLAYERS}} \
  -oldconsole -servergamelog -NoBattlEye \
  & ARK_PID=$!

# Then tails logs:
tail -c0 -F ./ShooterGame/Saved/Logs/ShooterGame.log --pid=$ARK_PID
```

### Our Implementation
```bash
# We use similar approach but server exits before log tailing
$PROTON_PATH/proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
  $ASA_START_PARAMS & ARK_PID=$!
```

### Key Observations
1. Pelican uses background process (`&`) with PID tracking - **We implemented this**
2. Pelican uses `-oldconsole -servergamelog` flags - **We have these**
3. Pelican waits for RCON before considering ready - **We implemented this**
4. Pelican uses relative binary path - **We fixed this**

## Remaining Issues to Investigate

### 1. Game Version Compatibility
- **Check**: Is the ARK server version the same between containers?
- **Test**: Try downloading an older server version
- **Command**: Check build ID in SteamCMD

### 2. Proton Version Differences
- **Current**: GE-Proton10-17
- **Test**: Try GE-Proton9-x or GE-Proton8-x
- **Note**: Older versions use different Steam Runtime

### 3. Missing Windows Components
Despite vcredist installation, may need:
- DirectX 9/11 components (d3dx9, d3dcompiler)
- .NET Framework
- Media Foundation codecs

### 4. Steam Client Integration
- **Current**: Using steam_appid.txt
- **Test**: Try running with Steam client libraries
- **Check**: Pelican might have additional Steam stubs

### 5. Launch Parameter Issues
- **Test**: Minimal parameters (just map name)
- **Test**: Without `-oldconsole` or `-servergamelog`
- **Test**: Different map names

## Simplified Test Script

Create a minimal test script to isolate the issue:

```bash
#!/bin/bash
cd /home/gameserver/server-files

# Minimal environment
export XDG_RUNTIME_DIR=/tmp/runtime-gameserver
mkdir -p "$XDG_RUNTIME_DIR"
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/Steam
export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/steamapps/compatdata/2430930
export PROTON_NO_ESYNC=1
export PROTON_NO_FSYNC=1

# Create steam_appid.txt
echo "2430930" > steam_appid.txt

# Try minimal launch
/home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/proton run \
  ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
  TheIsland_WP?listen -log
```

## Next Steps

### Priority 1: Get Pelican Configuration
1. Access Pelican Panel admin interface
2. Export the ARK Ascended egg JSON
3. Check Docker image used (likely `ghcr.io/parkervcp/yolks:wine_latest`)
4. Get exact startup command from running container

### Priority 2: Enable Wine Debug Output
```bash
export WINEDEBUG=+all
export PROTON_LOG=1
export PROTON_DUMP_DEBUG_COMMANDS=1
```

### Priority 3: Test Different Proton Versions
```bash
# Download and test:
- GE-Proton9-20
- GE-Proton8-32
- Proton 8.0 (official)
```

### Priority 4: Compare Running Processes
On Pelican server that works:
```bash
ps aux | grep -E "Ark|wine|proton"
lsof -p [ARK_PID] | head -50
cat /proc/[ARK_PID]/environ
```

### Priority 5: Simplify Container
Remove from start_server:
- Plugin loader logic
- Complex retry mechanisms
- Config file imports
- Just focus on basic launch

## Commands for Investigation

### Check Pelican Container
```bash
# If you have access to Pelican host:
docker ps | grep ark
docker inspect [container_id] | grep -A10 "Env"
docker exec [container_id] cat /entrypoint.sh
```

### Test Wine/Proton Directly
```bash
# Test if Wine works at all:
proton run notepad.exe
proton run cmd.exe /c "echo test"
```

### Check for Missing Libraries
```bash
# In debug container:
ldd ./ShooterGame/Binaries/Win64/*.so 2>/dev/null
find /home/gameserver/server-files -name "*.dll" -exec file {} \;
```

## Hypothesis

The most likely causes for the silent crash are:

1. **Steam API Initialization** - Despite steam_appid.txt, the server may need additional Steam client components
2. **Missing Windows Runtime** - A specific DLL or Windows component not provided by Wine
3. **Proton Compatibility** - The specific game build may not work with GE-Proton10-17
4. **Launch Parameter Format** - The parameter parsing might fail silently

## Files Modified

1. `/root/usr/bin/start_server` - Main startup script
2. `Dockerfile` - Added 32-bit dependencies
3. `docker-compose.yml` - Added ulimits

## Test Results Log

| Test | Result | Notes |
|------|--------|-------|
| Original container | ❌ Crash | Wine path errors, Steam API crash |
| + Working directory fix | ❌ Crash | Path errors fixed, still crashes |
| + steam_appid.txt | ❌ Crash | No Steam API errors, but still exits |
| + 32-bit deps | ❌ Crash | Libraries loaded, process still exits |
| + XDG_RUNTIME_DIR | ❌ Crash | No XDG errors, silent exit |
| + All fixes | ❌ Crash | All errors fixed, silent exit remains |

## Conclusion

We've successfully fixed all infrastructure and Wine/Proton setup issues. The remaining problem appears to be game-specific compatibility. The next step is to obtain the exact Pelican configuration and compare it with our setup to identify the missing piece.

The fact that Pelican's version works proves ARK CAN run in Docker with Wine/Proton - we just need to find the right configuration.