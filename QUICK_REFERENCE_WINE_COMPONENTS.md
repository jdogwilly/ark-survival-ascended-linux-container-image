# Quick Reference: Wine Components, Winetricks, and ProtonFixes for ARK:SA

**Purpose**: Fast lookup guide for Wine/Proton components, packages, and environment variables
**Format**: Quick reference tables and checklists
**Use When**: Need quick answers about specific components

---

## Wine Component Quick Reference

### What is "Wine"?
Wine = Windows Compatibility Layer
- Translates Windows API calls to Linux equivalents
- Allows Windows programs to run on Linux
- Used by Proton (Valve's Wine wrapper for games)

### What is "Proton"?
Proton = Wine + Game Tweaks + Performance Layer
- Based on Wine but customized for game compatibility
- Adds DXVK (DirectX to Vulkan translation)
- Includes VKD3D (DirectX 12 to Vulkan translation)
- Includes ProtonFixes (game-specific patches)
- Used by Steam for running Windows games on Linux

### What is "GE-Proton"?
GE-Proton = Community-maintained Proton
- Maintained by GloriousEggroll
- More game fixes than official Proton
- More frequent updates
- Better compatibility overall

---

## Critical Components for ARK:SA

| Component | What It Is | ARK:SA Needs? | Status |
|-----------|-----------|---------------|--------|
| **steamclient.so** | Steam client library | YES (CRITICAL) | ❌ MISSING |
| **vcrun2019** | Visual C++ 2019 Runtime | YES (CRITICAL) | ✅ INSTALLED |
| **d3dx9** | DirectX 9 compatibility | OPTIONAL | ⚠️ NOT INSTALLED |
| **mf/mfplat** | Media Foundation | OPTIONAL | ⚠️ NOT INSTALLED |
| **wined3d** | DirectX to OpenGL backend | Optional | ✅ Available in Proton |
| **DXVK** | DirectX to Vulkan backend | Used by Proton | ✅ In GE-Proton |
| **VKD3D** | DirectX 12 to Vulkan | Used by Proton | ✅ In GE-Proton |

**Key Finding**: We're missing `steamclient.so` which is the most critical component.

---

## Winetricks Packages for ARK:SA

### How to Install Winetricks

```bash
# Method 1: System package manager
apt-get install winetricks

# Method 2: Manual download
wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x winetricks
sudo mv winetricks /usr/local/bin/

# Method 3: Via pip (for protontricks)
pip install protontricks
```

### Essential Packages

| Package | Purpose | Install | ARK:SA |
|---------|---------|---------|--------|
| **vcrun2019** | Visual C++ 2019 Runtime | `winetricks vcrun2019` | CRITICAL |
| **d3dx9** | DirectX 9 libraries | `winetricks d3dx9` | Optional |
| **d3dcompiler_47** | DirectX shader compiler | `winetricks d3dcompiler_47` | Optional |
| **wined3d=enabled** | DirectX via OpenGL | `winetricks wined3d=enabled` | Fallback only |
| **gdiplus** | Graphics Device Interface | `winetricks gdiplus` | Optional |
| **dotnet48** | .NET Framework | `winetricks dotnet48` | Not needed |
| **mf** | Media Foundation | `winetricks mf` | Optional |

### Installation Syntax

```bash
# Set Wine prefix first
export WINEPREFIX=/path/to/wine/prefix

# Install a package
winetricks vcrun2019

# Install multiple packages
winetricks vcrun2019 d3dx9 d3dcompiler_47

# With Proton (use protontricks)
export PROTON_VERSION=GE-Proton10-25
protontricks 2430930 vcrun2019

# Check what's installed
winetricks list-installed
```

### For ARK:SA Servers Specifically

```bash
# Minimum for servers (usually not needed if Steam client libs present)
# Servers don't render, so graphics packages unnecessary

# If server crashes, try:
winetricks vcrun2019 d3dx9 d3dcompiler_47

# Or with protontricks:
PROTON_VERSION=GE-Proton10-25 protontricks 2430930 vcrun2019
```

---

## ProtonFixes Quick Reference

### What ProtonFixes Does

| Function | Example | Impact |
|----------|---------|--------|
| **Environment Variables** | Set `PULSE_LATENCY_MSEC` for audio | Fixes audio issues |
| **Executable Replacement** | Launch game.exe instead of launcher.exe | Fixes startup crashes |
| **Winetricks Integration** | Install `ole32` component | Fixes missing DLLs |
| **DLL Overrides** | Set `dxvk.dll=native` | Forces specific DLL version |
| **Video Codec Fixes** | Install media components | Fixes video playback |

### Unit Test Mode Detection

**When ProtonFixes enters unit test mode:**
- Missing `SteamAppId` or `SteamGameId` environment variable
- Missing valid `STEAM_COMPAT_CLIENT_INSTALL_PATH`
- Running outside normal Steam launcher context
- Incorrect Wine prefix configuration

**Fix for ARK:SA:**
```bash
export SteamAppId=2430930
export SteamGameId=2430930
export SRCDS_APPID=2430930  # For dedicated servers
```

### Warning Message Explained

```
ProtonFixes[12345] WARN: Skipping fix execution. We are probably running an unit test.
```

| Aspect | Details |
|--------|---------|
| **When it appears** | During Proton startup |
| **What it means** | ProtonFixes detected non-standard environment |
| **Is it fatal?** | NO - game usually still launches |
| **Why it matters** | Game-specific fixes won't be applied |
| **How to fix** | Set proper environment variables (see above) |

**For ARK:SA servers:**
- This warning is not critical IF Steam client libraries are installed
- But it indicates configuration isn't ideal

---

## Environment Variables Cheat Sheet

### Critical Variables

```bash
# Steam Application Identification
export SteamAppId=2430930                # Standard Steam app ID
export SteamGameId=2430930               # Alternative Steam game ID
export SRCDS_APPID=2430930               # Source Dedicated Server app ID (for servers)

# Wine/Proton Paths
export WINEPREFIX=/path/to/prefix        # Wine prefix directory
export WINEARCH=win64                    # Windows architecture (win64 or win32)

# Steam Compatibility Layer
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/path/to/steam
export STEAM_COMPAT_DATA_PATH=/path/to/compatdata/2430930/pfx

# XDG Runtime
export XDG_RUNTIME_DIR=/tmp/runtime-gameserver
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
```

### Performance Variables

```bash
# Disable synchronization (for containers, improves stability)
export PROTON_NO_ESYNC=1                 # Disable eventfd-based synchronization
export PROTON_NO_FSYNC=1                 # Disable futex-based synchronization

# DirectX Backend
export DXVK_HUD=0                        # Disable DXVK HUD overlay
export DXVK_LOG_LEVEL=error              # Logging level
export PROTON_USE_WINED3D=0              # Use DXVK (1 = WineD3D, slower)
```

### Debug Variables

```bash
# Proton Logging
export PROTON_LOG=1                      # Enable Proton logging
export PROTON_LOG_DIR=/path/to/logs      # Log directory
export PROTON_DUMP_DEBUG_COMMANDS=1      # Dump debug info

# Wine Debugging
export WINEDEBUG="-all,+loaddll,+err"   # Specific debug channels
export WINEDEBUG="+all"                  # Everything (very verbose!)
```

### For ARK:SA Servers

```bash
# Minimum configuration
export SteamAppId=2430930
export SRCDS_APPID=2430930
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/Steam
export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/steamapps/compatdata/2430930

# Recommended configuration
export SteamAppId=2430930
export SteamGameId=2430930
export SRCDS_APPID=2430930
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/server-files/.steam/steam
export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/.steam/steam/steamapps/compatdata/2430930
export PROTON_NO_ESYNC=1
export PROTON_NO_FSYNC=1
export XDG_RUNTIME_DIR=/tmp/runtime-gameserver
```

---

## DirectX Component Table

### DirectX Versions and Proton Support

| Version | Shader Model | Proton Support | ARK:SA Use |
|---------|--------------|----------------|-----------|
| **DirectX 9** | SM 3.0 | ✅ Full | Legacy |
| **DirectX 10** | SM 4.0 | ⚠️ Partial | Legacy |
| **DirectX 11** | SM 5.0 | ✅ Full (DXVK) | Fallback |
| **DirectX 12** | SM 6.0 | ⚠️ Partial (VKD3D) | Primary |

### Key DirectX Components

| Component | What It Does | Installed Via |
|-----------|-------------|----------------|
| **d3dx9** | DirectX 9 compatibility DLLs | winetricks d3dx9 |
| **d3dcompiler_43** | Shader compiler (older) | winetricks d3dcompiler_43 |
| **d3dcompiler_47** | Shader compiler (newer) | winetricks d3dcompiler_47 |
| **dxvk** | DirectX to Vulkan | Built into Proton |
| **vkd3d** | DirectX 12 to Vulkan | Built into Proton |
| **wined3d** | DirectX to OpenGL | Built into Wine |

### Which DirectX Translator is Used?

```
ARK:SA DirectX 12 Call
    ↓
Proton checks for: Is PROTON_USE_WINED3D=1?
    ├─→ YES: Use WineD3D (OpenGL backend) - SLOWER
    └─→ NO:  Use DXVK/VKD3D (Vulkan backend) - FASTER (default)
    ↓
Vulkan Call
    ↓
GPU
```

**For ARK:SA servers:**
- Keep default (DXVK/VKD3D) - servers don't render
- If startup crashes, try `PROTON_USE_WINED3D=1` as fallback

---

## System Requirements Checklist

### For ARK:SA Server Container

```bash
# Required on Docker host
✓ 15GB free disk space (at least)
✓ vm.max_map_count=262144 (critical!)
✓ Adequate RAM (13GB+ for server process)
✓ Reasonable CPU (2+ cores)

# Set vm.max_map_count on host:
sudo sysctl vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf  # Persist
```

### Inside Container

```bash
# Installed packages
✓ 32-bit library support (i386 architecture)
✓ Proton/GE-Proton (for Windows compatibility)
✓ SteamCMD (for downloading server files)
✓ Basic tools: wget, tar, unzip, python3
✓ Audio libraries: libasound2, libpulse0
✓ Graphics libraries: libgl1-mesa, SDL2

# Missing (that we need to add)
✗ Steam client libraries (App 1007)
✗ steamclient.so stubs (.steam/sdk32/, .steam/sdk64/)
```

---

## Directory Structure Reference

### Current Directory Structure

```
/home/gameserver/
├── Steam/                                    # Steam client
│   └── compatibilitytools.d/
│       └── GE-Proton10-17/                  # Proton installation
├── steamcmd/                                 # SteamCMD installation
│   ├── linux32/
│   │   └── steamclient.so  ← WE NEED TO COPY THIS
│   └── linux64/
│       └── steamclient.so  ← WE NEED TO COPY THIS
└── server-files/                             # ARK game files
    ├── ShooterGame/
    │   └── Binaries/
    │       └── Win64/
    │           └── ArkAscendedServer.exe    # Server binary
    ├── steam_appid.txt
    └── steamapps/
        └── compatdata/
            └── 2430930/
                └── pfx/                     # Wine prefix
```

### Required Directory Structure

```
/home/gameserver/server-files/
├── .steam/                                   # MISSING!
│   ├── sdk32/
│   │   └── steamclient.so  ← NEED TO CREATE & COPY
│   └── sdk64/
│       └── steamclient.so  ← NEED TO CREATE & COPY
└── [rest of structure stays the same]
```

### Pelican-Compatible Structure (Optional)

```
/home/gameserver/server-files/
├── .steam/
│   ├── sdk32/
│   │   └── steamclient.so
│   ├── sdk64/
│   │   └── steamclient.so
│   └── steam/                               # Symlink to steamapps
│       └── steamapps → (symlink to ../../../steamapps)
│           └── compatdata/
│               └── 2430930/
│                   └── pfx/
```

---

## Troubleshooting Decision Tree

### Server exits immediately (exit code 1)

```
Does server have steamclient.so?
├─→ NO  → Install Steam client libraries (App 1007) → Copy .so files
├─→ YES → Is SRCDS_APPID set?
    ├─→ NO  → Set SRCDS_APPID=2430930 environment variable
    └─→ YES → Update Proton to 10-25 or test with different version
```

### ProtonFixes unit test mode warning

```
Is SteamAppId set?
├─→ NO  → Set export SteamAppId=2430930
├─→ YES → Is STEAM_COMPAT_CLIENT_INSTALL_PATH valid?
    ├─→ NO  → Set valid path to Steam installation
    └─→ YES → Set SRCDS_APPID=2430930 for dedicated server
```

### RCON doesn't work

```
Is server process running?
├─→ NO  → Fix server startup first (likely missing Steam libs)
├─→ YES → Is wine prefix initialized?
    ├─→ NO  → Run wineboot --init
    └─→ YES → Is RCON_PORT correct?
        ├─→ YES → Check server admin password is set
        └─→ NO  → Fix port configuration
```

### Logs not updating

```
Is server process still running?
├─→ NO  → Server crashed (check for missing components)
├─→ YES → Check logs directory exists:
    └─→ /home/gameserver/server-files/ShooterGame/Saved/Logs/
```

---

## Quick Fixes Cheat Sheet

### Fix 1: Install Steam Client Libraries (CRITICAL)

```bash
# In start_server, add after SteamCMD download:
cd /home/gameserver/steamcmd
./steamcmd.sh +force_install_dir /home/gameserver/server-files +login anonymous +app_update 1007 +quit

mkdir -p /home/gameserver/server-files/.steam/sdk32
mkdir -p /home/gameserver/server-files/.steam/sdk64
cp /home/gameserver/steamcmd/linux32/steamclient.so /home/gameserver/server-files/.steam/sdk32/
cp /home/gameserver/steamcmd/linux64/steamclient.so /home/gameserver/server-files/.steam/sdk64/
```

**Why**: Provides Steam API library ARK needs

### Fix 2: Set SRCDS_APPID (IMPORTANT)

```bash
# In docker-compose.yml:
environment:
  - SRCDS_APPID=2430930

# Or in start_server:
export SRCDS_APPID=2430930
```

**Why**: Signals dedicated server mode to Proton

### Fix 3: Update Proton (RECOMMENDED)

```bash
# In start_server, change:
PROTON_VERSION="10-25"  # From 10-17
```

**Why**: Newer version has more ARK fixes

### Fix 4: System Setting (REQUIRED)

```bash
# On host system:
sudo sysctl vm.max_map_count=262144
```

**Why**: ARK needs high memory mapping count

---

## Related Documentation

### Comprehensive Guides
- `WINE_FIXES_AND_WINETRICKS_RESEARCH.md` - Full research with sources
- `PELICAN_COMPARISON_REPORT.md` - Detailed Pelican analysis
- `RESEARCH_SUMMARY_AND_ACTION_ITEMS.md` - Executive summary

### Implementation Guides
- `QUICK_FIX_GUIDE.md` - 5-minute fix
- `TROUBLESHOOTING_REPORT.md` - Issues and solutions

### Configuration
- `CLAUDE.md` - Project documentation
- `README.md` - User guide

---

## Useful Commands

### Install Winetricks
```bash
wget -q -O /usr/local/bin/winetricks \
  https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x /usr/local/bin/winetricks
```

### Verify Steam Client Libraries
```bash
# Check if files exist
ls -la /home/gameserver/steamcmd/linux32/steamclient.so
ls -la /home/gameserver/steamcmd/linux64/steamclient.so

# Check if installed in server directory
ls -la /home/gameserver/server-files/.steam/sdk32/steamclient.so
ls -la /home/gameserver/server-files/.steam/sdk64/steamclient.so
```

### Test Wine/Proton Functionality
```bash
# Test if Wine prefix is initialized
test -d /path/to/prefix/pfx/drive_c && echo "Wine prefix exists" || echo "No Wine prefix"

# Test Proton
/path/to/GE-Proton10-25/proton --version

# Test SteamCMD
/home/gameserver/steamcmd/steamcmd.sh +login anonymous +quit
```

### View Environment Variables
```bash
# Show all relevant variables
env | grep -E "STEAM|PROTON|WINE|SteamApp"

# Show specific variable
echo $STEAM_COMPAT_DATA_PATH
echo $SRCDS_APPID
```

---

## Key Takeaways

1. **Missing Steam Client Libraries** ← THE PROBLEM
2. **steamclient.so in .steam/sdk32/ and sdk64/** ← THE SOLUTION
3. **Set SRCDS_APPID=2430930** ← IMPORTANT CONFIG
4. **Update Proton to 10-25** ← RECOMMENDED
5. **Set vm.max_map_count=262144 on host** ← REQUIRED FOR STABILITY

---

**Last Updated**: November 2025
**Format**: Quick Reference Guide
**Use For**: Fast lookups, troubleshooting, implementation
