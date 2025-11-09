#!/bin/bash

# ARK Survival Ascended Container Environment Validation Script
# This script validates that all required components are properly installed

set -euo pipefail

echo "=========================================="
echo "ARK: Survival Ascended Environment Validator"
echo "=========================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

echo "=== 1. Directory Structure ==="

# Check server files directory
if [ -d "/home/gameserver/server-files" ]; then
    check_pass "Server files directory exists"
else
    check_fail "Server files directory missing: /home/gameserver/server-files"
fi

# Check Steam directory
if [ -d "/home/gameserver/Steam" ]; then
    check_pass "Steam directory exists"
else
    check_fail "Steam directory missing: /home/gameserver/Steam"
fi

# Check SteamCMD directory
if [ -d "/home/gameserver/steamcmd" ]; then
    check_pass "SteamCMD directory exists"
else
    check_fail "SteamCMD directory missing: /home/gameserver/steamcmd"
fi

echo ""
echo "=== 2. Steam Client Libraries (CRITICAL) ==="

# Check for Steam client libraries
if [ -f "/home/gameserver/server-files/.steam/sdk32/steamclient.so" ]; then
    check_pass "32-bit steamclient.so installed"
else
    check_fail "32-bit steamclient.so MISSING - Server will crash!"
fi

if [ -f "/home/gameserver/server-files/.steam/sdk64/steamclient.so" ]; then
    check_pass "64-bit steamclient.so installed"
else
    check_fail "64-bit steamclient.so MISSING - Server will crash!"
fi

# Check for Steam Linux Runtime
if [ -d "/home/gameserver/server-files/linux32" ] || [ -d "/home/gameserver/server-files/linux64" ]; then
    check_pass "Steam Linux Runtime directories found"
else
    check_warn "Steam Linux Runtime directories not found (may need App 1007)"
fi

echo ""
echo "=== 3. ARK Server Binary ==="

# Check for ARK server executable
ARK_BINARY="/home/gameserver/server-files/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
if [ -f "$ARK_BINARY" ]; then
    check_pass "ARK server binary exists"
    # Check file size (should be > 100MB)
    SIZE=$(stat -c%s "$ARK_BINARY")
    if [ "$SIZE" -gt 104857600 ]; then
        check_pass "ARK server binary size OK: $(($SIZE / 1048576))MB"
    else
        check_warn "ARK server binary seems small: $(($SIZE / 1048576))MB"
    fi
else
    check_fail "ARK server binary missing: $ARK_BINARY"
fi

echo ""
echo "=== 4. Critical DLLs ==="

# Check for required DLLs
REQUIRED_DLLS=(
    "steam_api64.dll"
    "tier0_s64.dll"
    "vstdlib_s64.dll"
)

for DLL in "${REQUIRED_DLLS[@]}"; do
    if [ -f "/home/gameserver/server-files/ShooterGame/Binaries/Win64/$DLL" ]; then
        check_pass "Required DLL present: $DLL"
    else
        check_fail "Required DLL missing: $DLL"
    fi
done

echo ""
echo "=== 5. Steam AppID Configuration ==="

# Check steam_appid.txt
if [ -f "/home/gameserver/server-files/steam_appid.txt" ]; then
    APPID=$(cat /home/gameserver/server-files/steam_appid.txt)
    if [ "$APPID" = "2430930" ]; then
        check_pass "steam_appid.txt correctly configured (2430930)"
    else
        check_fail "steam_appid.txt has wrong AppID: $APPID (should be 2430930)"
    fi
else
    check_fail "steam_appid.txt missing - Steam API will fail!"
fi

echo ""
echo "=== 6. Proton Installation ==="

# Check Proton version
PROTON_VERSION="10-25"
PROTON_DIR="/home/gameserver/Steam/compatibilitytools.d/GE-Proton${PROTON_VERSION}"

if [ -d "$PROTON_DIR" ]; then
    check_pass "Proton GE-${PROTON_VERSION} installed"

    # Check Proton binary
    if [ -f "$PROTON_DIR/proton" ]; then
        check_pass "Proton executable found"
    else
        check_fail "Proton executable missing in $PROTON_DIR"
    fi

    # Check Wine binaries
    if [ -f "$PROTON_DIR/files/bin/wine64" ]; then
        check_pass "Wine64 binary found"
    else
        check_fail "Wine64 binary missing"
    fi
else
    check_warn "Proton GE-${PROTON_VERSION} not installed (will be downloaded on first run)"
fi

echo ""
echo "=== 7. Wine Prefix ==="

# Check Wine prefix
WINE_PREFIX="/home/gameserver/server-files/steamapps/compatdata/2430930/pfx"
if [ -d "$WINE_PREFIX/drive_c" ]; then
    check_pass "Wine prefix initialized"

    # Check for VC++ redistributables
    if ls "$WINE_PREFIX/drive_c/windows/system32/msvc"*.dll >/dev/null 2>&1; then
        check_pass "Visual C++ redistributables installed"
    else
        check_warn "Visual C++ redistributables may not be installed"
    fi
else
    check_warn "Wine prefix not initialized (will be created on first run)"
fi

echo ""
echo "=== 8. System Resources ==="

# Check file descriptor limits
ULIMIT_N=$(ulimit -n)
if [ "$ULIMIT_N" -ge 100000 ]; then
    check_pass "File descriptor limit OK: $ULIMIT_N"
else
    check_fail "File descriptor limit too low: $ULIMIT_N (need 100000+)"
    echo "  Fix: Add ulimits to docker-compose.yml or use --ulimit nofile=100000:100000"
fi

# Check available disk space
AVAILABLE_SPACE=$(df /home/gameserver/server-files | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_SPACE / 1048576))
if [ "$AVAILABLE_GB" -ge 20 ]; then
    check_pass "Disk space available: ${AVAILABLE_GB}GB"
else
    check_warn "Low disk space: ${AVAILABLE_GB}GB (recommend 20GB+)"
fi

echo ""
echo "=== 9. Environment Variables ==="

# Check critical environment variables
ENV_VARS=(
    "XDG_RUNTIME_DIR"
    "STEAM_COMPAT_CLIENT_INSTALL_PATH"
    "STEAM_COMPAT_DATA_PATH"
)

for VAR in "${ENV_VARS[@]}"; do
    if [ -n "${!VAR:-}" ]; then
        check_pass "$VAR is set: ${!VAR}"
    else
        check_warn "$VAR not set (will be set during startup)"
    fi
done

echo ""
echo "=== 10. Quick Wine Test ==="

# Try to run a simple Wine command if Proton is installed
if [ -d "$PROTON_DIR" ]; then
    echo "Testing Wine/Proton basic functionality..."
    export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/steamapps/compatdata/2430930
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-gameserver}
    mkdir -p "$XDG_RUNTIME_DIR"

    if timeout 5s "$PROTON_DIR/files/bin/wine64" --version >/dev/null 2>&1; then
        check_pass "Wine64 executable works"
    else
        check_fail "Wine64 executable failed to run"
    fi

    # Try Proton
    if timeout 5s "$PROTON_DIR/proton" run cmd.exe /c "echo test" 2>&1 | grep -q "test"; then
        check_pass "Proton can execute Windows commands"
    else
        check_warn "Proton execution test failed (may need initialization)"
    fi
else
    check_warn "Skipping Wine test - Proton not installed"
fi

echo ""
echo "=========================================="
echo "VALIDATION SUMMARY"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC} $FAILED"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ Environment is ready for ARK server!${NC}"
    echo ""
    echo "To test the server launch with minimal parameters:"
    echo "  docker exec -it asa-server bash"
    echo "  cd /home/gameserver/server-files"
    echo "  /home/gameserver/Steam/compatibilitytools.d/GE-Proton10-25/proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe TheIsland_WP -log"
    exit 0
else
    echo -e "${RED}✗ Environment has critical issues that must be fixed!${NC}"
    echo ""
    echo "Most likely fix needed:"
    echo "1. Run the container once to download server files"
    echo "2. The new start_server script will install Steam client libraries"
    echo "3. Re-run this validation script"
    exit 1
fi