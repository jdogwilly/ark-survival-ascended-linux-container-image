# ARK Server Container Fix Report

## Executive Summary
The ARK Survival Ascended server container is failing to run due to multiple issues. The server process launches but exits within 2-10 seconds with exit code 1.

## Critical Issues Identified

### 1. **ProtonFixes Unit Test Mode** 🔴
```
ProtonFixes[PID] WARN: Skipping fix execution. We are probably running an unit test.
```
- **Impact**: Proton is not applying necessary game-specific fixes
- **Cause**: Missing or incorrect environment configuration

### 2. **Wine Working Directory Error** 🔴
```
wine: could not open working directory L"unix\home\gameserver\steamcmd\", starting in the Windows directory.
```
- **Impact**: Wine cannot find the correct working directory
- **Fix Applied**: Created symlink `/home/gameserver/steamcmd -> /home/gameserver/Steam`

### 3. **XDG_RUNTIME_DIR Missing** 🟡
```
error: XDG_RUNTIME_DIR is invalid or not set in the environment.
```
- **Impact**: Runtime directory required for various Linux services
- **Fix Applied**: `export XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)`

### 4. **ProtonFixes Config Directory Missing** 🟡
```
ProtonFixes[506] WARN: [CONFIG]: Parent directory "/home/gameserver/.config/protonfixes" does not exist.
```
- **Impact**: ProtonFixes cannot save/load configuration
- **Fix Applied**: `mkdir -p /home/gameserver/.config/protonfixes`

### 5. **SteamCMD Permission Issues** 🟡
- **First Run**: Permission denied when downloading steamcmd_linux.tar.gz
- **Impact**: Container fails on first startup
- **Status**: Works on container restart

## Test Results

| Test | Duration | Exit Code | Notes |
|------|----------|-----------|-------|
| Original Setup | ~10 seconds | 1 | Dies waiting for RCON |
| With Wine Fix | ~2 seconds | 1 | Dies faster |
| With XDG Fix | ~2 seconds | 1 | No improvement |
| With All Fixes | ~2 seconds | 1 | Still failing |

## Root Cause Analysis

The server is likely failing because:
1. **Proton is in "unit test" mode** and not applying game fixes
2. **Missing Windows runtime components** (DirectX, Media Foundation)
3. **Possible anti-cheat conflicts** (BattlEye/EasyAntiCheat)
4. **Incorrect Proton version** for this ARK build

## Recommended Solutions

### Option 1: Switch to Pelican's Base Image (RECOMMENDED)
```dockerfile
FROM ghcr.io/parkervcp/yolks:wine_latest

# Copy server files
COPY --chown=1000:1000 server-files /home/container/server-files

# Set working directory
WORKDIR /home/container/server-files

# Use their startup approach
CMD ["proton", "run", "./ShooterGame/Binaries/Win64/ArkAscendedServer.exe", "TheIsland_WP?listen", "-log"]
```

### Option 2: Fix ProtonFixes Unit Test Mode
```bash
# Add to start_server script
export PROTONFIXES_DISABLE_PROTON_UNIT_TEST=1
export STEAM_RUNTIME_PREFER_HOST_LIBRARIES=0
export PROTON_NO_ESYNC=0
export PROTON_NO_FSYNC=0
```

### Option 3: Try Different Proton Version
```bash
# Test with GE-Proton9-20 (more stable)
wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20.tar.gz
tar -xzf GE-Proton9-20.tar.gz
```

### Option 4: Install Missing Components
```bash
# Install DirectX and Media Foundation
winetricks d3dx9 d3dcompiler_43 d3dcompiler_47
winetricks mf mfplat
```

## Files to Modify

1. **`/usr/bin/start_server`**:
   - Add XDG_RUNTIME_DIR export
   - Fix steamcmd symlink creation
   - Add ProtonFixes config directory creation
   - Add PROTONFIXES_DISABLE_PROTON_UNIT_TEST=1

2. **`Dockerfile`**:
   - Consider switching base image to `ghcr.io/parkervcp/yolks:wine_latest`
   - Add strace package for debugging
   - Pre-create required directories

3. **`docker-compose.yml`**:
   - Add missing environment variables
   - Ensure proper volume permissions

## Next Steps

1. **IMMEDIATE**: Test with Pelican's base image
2. **SHORT TERM**: Fix ProtonFixes unit test mode
3. **MEDIUM TERM**: Document working configuration
4. **LONG TERM**: Create automated tests

## Validation Commands

```bash
# Check if container is healthy
docker ps | grep asa

# Monitor server process
docker exec asa-server pgrep -f ArkAscended

# Check for game logs
docker exec asa-server ls -la /home/gameserver/server-files/ShooterGame/Saved/Logs/

# View Wine errors
docker logs asa-server 2>&1 | grep -i "wine\|proton\|error"
```

## Conclusion

The container has multiple overlapping issues, with the ProtonFixes "unit test" mode being the most critical. The fastest solution is to adopt Pelican's proven approach using their Wine base image.