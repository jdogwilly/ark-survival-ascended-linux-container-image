#!/bin/bash

# Minimal ARK Server Launch Test Script
# Tests if the server can start with the fixes applied

set -euo pipefail

echo "=================================================="
echo "ARK: Survival Ascended - Minimal Launch Test"
echo "=================================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Configuration
SERVER_DIR="/home/gameserver/server-files"
PROTON_VERSION="10-25"
PROTON_PATH="/home/gameserver/Steam/compatibilitytools.d/GE-Proton${PROTON_VERSION}"
LOG_FILE="/home/gameserver/server-files/minimal_test_$(date +%Y%m%d_%H%M%S).log"

echo "Test configuration:"
echo "  Server directory: $SERVER_DIR"
echo "  Proton version: GE-Proton${PROTON_VERSION}"
echo "  Log file: $LOG_FILE"
echo ""

# Step 1: Verify critical components
echo "=== Step 1: Verifying Critical Components ==="

if [ ! -f "$SERVER_DIR/.steam/sdk64/steamclient.so" ]; then
    log_error "CRITICAL: steamclient.so not found!"
    log_error "The Steam client libraries are missing. This is why the server crashes."
    echo ""
    echo "To fix this, run:"
    echo "  docker-compose up asa-server"
    echo "The updated start_server script will install the Steam client libraries."
    exit 1
fi
log_info "steamclient.so found ✓"

if [ ! -f "$SERVER_DIR/steam_appid.txt" ]; then
    log_warn "steam_appid.txt missing, creating it..."
    echo "2430930" > "$SERVER_DIR/steam_appid.txt"
fi
log_info "steam_appid.txt configured ✓"

if [ ! -d "$PROTON_PATH" ]; then
    log_error "Proton GE-${PROTON_VERSION} not installed!"
    echo "Please run the container first to download Proton."
    exit 1
fi
log_info "Proton installed ✓"

echo ""
echo "=== Step 2: Setting Up Environment ==="

# Set up minimal environment
export XDG_RUNTIME_DIR=/tmp/runtime-gameserver
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

export STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/gameserver/Steam
export STEAM_COMPAT_DATA_PATH=/home/gameserver/server-files/steamapps/compatdata/2430930
export PROTON_NO_ESYNC=1
export PROTON_NO_FSYNC=1

# Use focused debugging to see what's happening
export WINEDEBUG="-all,+loaddll,+module,+seh,+err,+timestamp"
export PROTON_LOG=1
export PROTON_LOG_DIR="/home/gameserver/server-files"

# Steam environment
export SteamAppId=2430930
export SteamGameId=2430930

log_info "Environment configured ✓"

echo ""
echo "=== Step 3: Testing Minimal Launch ==="
echo ""
echo "Launching ARK server with minimal parameters..."
echo "Command: $PROTON_PATH/proton run ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe TheIsland_WP -log"
echo ""
echo "The server will run for 60 seconds. If it stays running, the fix worked!"
echo "Press Ctrl+C to stop early."
echo ""

# Change to server directory
cd "$SERVER_DIR"

# Launch the server with timeout
{
    timeout 60s "$PROTON_PATH/proton" run \
        ./ShooterGame/Binaries/Win64/ArkAscendedServer.exe \
        TheIsland_WP -log 2>&1 | tee "$LOG_FILE" &

    SERVER_PID=$!

    echo "Server launched with PID: $SERVER_PID"
    echo "Monitoring for 60 seconds..."
    echo ""

    # Monitor the process
    for i in {1..60}; do
        if ! ps -p $SERVER_PID > /dev/null 2>&1; then
            log_error "Server process died after $i seconds!"
            echo ""
            echo "Checking log for errors..."
            echo "----------------------------------------"
            tail -20 "$LOG_FILE" | grep -i "error\|fail\|exception\|crash" || echo "No obvious errors in log tail"
            echo "----------------------------------------"
            echo ""
            echo "The server crashed. Please check:"
            echo "1. Full log at: $LOG_FILE"
            echo "2. Wine debug output for DLL loading issues"
            echo "3. Whether Steam client libraries are properly installed"
            exit 1
        fi

        # Show progress every 10 seconds
        if [ $((i % 10)) -eq 0 ]; then
            echo "  [$i/60 seconds] Server still running... ✓"
        fi

        sleep 1
    done

    echo ""
    log_info "SUCCESS! Server ran for 60 seconds without crashing!"

    # Kill the server
    kill $SERVER_PID 2>/dev/null || true

} || {
    log_error "Test failed!"
    exit 1
}

echo ""
echo "=================================================="
echo "TEST RESULTS"
echo "=================================================="
echo ""
echo -e "${GREEN}✓ The ARK server started successfully!${NC}"
echo ""
echo "The fix worked! The server can now run without immediately crashing."
echo ""
echo "Next steps:"
echo "1. Test with full parameters in docker-compose.yml"
echo "2. Verify RCON connectivity"
echo "3. Check mod loading if using mods"
echo "4. Monitor for any remaining issues"
echo ""
echo "Full log saved to: $LOG_FILE"
echo ""

# Also check if ShooterGame.log was created
if [ -f "$SERVER_DIR/ShooterGame/Saved/Logs/ShooterGame.log" ]; then
    echo "Game log created at: $SERVER_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    echo "Last 10 lines of game log:"
    echo "----------------------------------------"
    tail -10 "$SERVER_DIR/ShooterGame/Saved/Logs/ShooterGame.log"
    echo "----------------------------------------"
fi