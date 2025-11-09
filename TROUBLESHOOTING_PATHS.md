# ARK Server Container - Troubleshooting Paths

## Current Status
✅ **FIXED**: Container initialization, SteamCMD, server download, Proton setup
⚠️ **ISSUE**: Server exits with code 3 after ~10 seconds
📍 **WHERE WE ARE**: Server launches but something at the application level causes exit

## Quick Test Commands

### Test in Kubernetes
```bash
# Check pod status
kubectl get pod asa-ragnarok-0 -n asa-cluster -o wide

# View logs
kubectl logs asa-ragnarok-0 -n asa-cluster --tail=200

# Debug exec into pod
kubectl exec -it asa-ragnarok-0 -n asa-cluster -- bash

# Check processes
kubectl exec asa-ragnarok-0 -n asa-cluster -- ps aux | grep -i ark
```

### Test Locally
```bash
# Quick test with our script
./test_fixed_with_permissions.sh

# Manual test with debug
docker run -it --rm \
  -e ENABLE_DEBUG=1 \
  -v asa-test-files:/home/gameserver/server-files \
  -v asa-test-steam:/home/gameserver/Steam \
  -v asa-test-steamcmd:/home/gameserver/steamcmd \
  asa-fixed:latest
```

---

## Path 1: Fix ProtonFixes Warning 🔧

The warning "Skipping fix execution. We are probably running an unit test" might be preventing game-specific fixes.

### Quick Fix
```bash
# In start_server, change line 22 from:
export PROTONFIXES_DISABLE_PROTON_UNIT_TEST=0

# To:
export PROTONFIXES_DISABLE_PROTON_UNIT_TEST=1
```

### Test in Running Container
```bash
docker exec asa-fixed-test bash -c '
  export PROTONFIXES_DISABLE_PROTON_UNIT_TEST=1
  cd /home/gameserver/server-files
  /home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/proton run \
    ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe TheIsland_WP -log
'
```

---

## Path 2: Add Windows Runtime Components 🪟

ARK might need additional Windows libraries.

### Quick Test with Winetricks
```bash
# Exec into container
docker exec -it asa-fixed-test bash

# Install winetricks (as root)
docker exec -u root asa-fixed-test apt update && apt install -y winetricks

# Install common components
docker exec asa-fixed-test bash -c '
  export WINEPREFIX=/home/gameserver/server-files/steamapps/compatdata/2430930/pfx
  winetricks vcrun2019 d3dx9 d3dcompiler_47
'
```

### Components to Try
- `vcrun2019` - Visual C++ 2019 Runtime
- `dotnet48` - .NET Framework 4.8
- `d3dx9` - DirectX 9 libraries
- `mf` - Media Foundation

---

## Path 3: Upgrade Proton Version 📦

We're using GE-Proton10-17, but newer versions might have fixes.

### Quick Test
```bash
# Download newer Proton in container
docker exec asa-fixed-test bash -c '
  cd /home/gameserver/Steam/compatibilitytools.d/
  wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-25/GE-Proton10-25.tar.gz
  tar -xzf GE-Proton10-25.tar.gz

  # Test with new version
  cd /home/gameserver/server-files
  /home/gameserver/Steam/compatibilitytools.d/GE-Proton10-25/proton run \
    ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe TheIsland_WP -log
'
```

### Permanent Fix
Update `start_server` line ~430:
```bash
PROTON_VERSION="10-25"  # Change from 10-17
```

---

## Path 4: Anti-Cheat Bypass 🛡️

ARK uses BattlEye which might be incompatible with Wine/Proton.

### Test Without BattlEye
```bash
# Add -NoBattlEye to launch parameters
docker exec asa-fixed-test bash -c '
  cd /home/gameserver/server-files
  /home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/proton run \
    ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
    TheIsland_WP?listen -NoBattlEye -log
'
```

### In Kubernetes
Add to environment:
```yaml
env:
- name: ASA_START_PARAMS
  value: "TheIsland_WP?listen -NoBattlEye -log"
```

---

## Path 5: Configuration Files 📄

Server might be failing due to missing/invalid config.

### Check Config Files
```bash
# List config directory
docker exec asa-fixed-test ls -la \
  /home/gameserver/server-files/ShooterGame/Saved/Config/WindowsServer/

# Create minimal GameUserSettings.ini
docker exec asa-fixed-test bash -c 'cat > /home/gameserver/server-files/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini << EOF
[ServerSettings]
ServerAdminPassword=test123
RCONEnabled=True
RCONPort=27020

[/Script/ShooterGame.ShooterGameUserSettings]
ServerName=Test Server
ServerPassword=
EOF'
```

---

## Path 6: Debug with strace 🔍

See exactly what's failing when the server exits.

### Install and Run strace
```bash
# Install strace (as root)
docker exec -u root asa-fixed-test apt update && apt install -y strace

# Run server with strace
docker exec asa-fixed-test bash -c '
  cd /home/gameserver/server-files
  strace -f -e trace=file,process -o /tmp/ark_strace.log \
    /home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/proton run \
    ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe TheIsland_WP -log

  # Check what failed
  tail -100 /tmp/ark_strace.log
'
```

---

## Path 7: Compare with Pelican's Exact Setup 🐧

Try matching Pelican's exact configuration.

### Key Differences to Test
1. **Steam directory structure** - They use different paths
2. **Proton launch method** - They might use different parameters
3. **Environment variables** - Check their exact env setup

### Get Pelican's Image
```bash
# Pull their wine image
docker pull ghcr.io/parkervcp/yolks:wine_latest

# Run and compare
docker run --rm -it ghcr.io/parkervcp/yolks:wine_latest env | sort
```

---

## Diagnostic Information to Collect

When testing, collect this info:

### 1. Process Information
```bash
ps aux | grep -i ark
pgrep -f ArkAscended
```

### 2. Wine/Proton Logs
```bash
# Check for Proton log
find /home/gameserver -name "steam-*.log" 2>/dev/null

# Wine errors
dmesg | grep -i wine
```

### 3. System Resources
```bash
df -h  # Disk space
free -h  # Memory
ulimit -a  # System limits
```

### 4. File Verification
```bash
# Check if executable exists and is valid
file /home/gameserver/server-files/ShooterGame/Binaries/Win64/ArkAscendedServer.exe
ls -la /home/gameserver/server-files/ShooterGame/Binaries/Win64/
```

---

## Priority Order to Try

1. **Path 4** - Anti-Cheat Bypass (-NoBattlEye) - Most likely culprit
2. **Path 1** - Fix ProtonFixes warning - Easy to test
3. **Path 3** - Upgrade Proton - Might have ARK-specific fixes
4. **Path 2** - Add Windows components - If missing dependencies
5. **Path 5** - Configuration files - If server needs specific settings
6. **Path 6** - strace debugging - To identify exact failure
7. **Path 7** - Match Pelican exactly - If all else fails

---

## Quick Win Combo Test

Try this combination that addresses multiple issues:

```bash
docker exec asa-fixed-test bash -c '
  # Fix ProtonFixes
  export PROTONFIXES_DISABLE_PROTON_UNIT_TEST=1

  # Ensure directories exist
  mkdir -p /home/gameserver/server-files/ShooterGame/Saved/Config/WindowsServer
  mkdir -p /home/gameserver/server-files/ShooterGame/Saved/Logs

  # Go to server directory
  cd /home/gameserver/server-files

  # Launch with multiple fixes
  /home/gameserver/Steam/compatibilitytools.d/GE-Proton10-17/proton run \
    ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
    TheIsland_WP?listen?RCONEnabled=True?RCONPort=27020 \
    -NoBattlEye -log -server
'
```

---

## Success Indicators

You'll know it's working when:
- Server stays running past 30 seconds
- Log shows "Server ready" or similar
- Process `ArkAscendedServer.exe` remains in `ps aux`
- RCON port (27020) becomes available
- Server appears in ARK server browser (if public)