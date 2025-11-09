#!/bin/bash

echo "========================================="
echo "ARK Server Container Fix Validation Test"
echo "========================================="
echo ""

# Stop any existing test container
echo "[1/5] Cleaning up old test containers..."
docker stop asa-fixed-test 2>/dev/null
docker rm asa-fixed-test 2>/dev/null

# Run the container with our fixes
echo "[2/5] Starting container with fixes..."
docker run -d \
  --name asa-fixed-test \
  -e ASA_START_PARAMS="TheIsland_WP?listen -WinLiveMaxPlayers=70 -Port=7777 -RCONPort=27020 -RCONEnabled=True -log" \
  -e ADMIN_PASSWORD="test123" \
  -v asa-fixed-server-files:/home/gameserver/server-files \
  -v asa-fixed-steam:/home/gameserver/Steam \
  -v asa-fixed-steamcmd:/home/gameserver/steamcmd \
  asa-fixed:latest

echo "[3/5] Waiting for container to initialize (10 seconds)..."
sleep 10

echo "[4/5] Checking container logs for critical errors..."
echo ""
echo "=== CHECKING FOR UNIT TEST MODE ERROR ==="
docker logs asa-fixed-test 2>&1 | grep -i "unit test" || echo "✓ No unit test mode error found"

echo ""
echo "=== CHECKING FOR STEAM CLIENT LIBRARIES ==="
docker exec asa-fixed-test ls -la /home/gameserver/server-files/.steam/sdk32/steamclient.so 2>&1 || echo "✗ 32-bit steamclient.so missing"
docker exec asa-fixed-test ls -la /home/gameserver/server-files/.steam/sdk64/steamclient.so 2>&1 || echo "✗ 64-bit steamclient.so missing"

echo ""
echo "=== CHECKING ENVIRONMENT VARIABLES ==="
docker exec asa-fixed-test bash -c 'env | grep -E "SRCDS_APPID|SteamAppId|STEAM_COMPAT|XDG_RUNTIME"'

echo ""
echo "=== MONITORING SERVER STARTUP (30 seconds) ==="
echo "Watching for server process..."

for i in {1..30}; do
  if docker exec asa-fixed-test pgrep -f "ArkAscended" > /dev/null 2>&1; then
    echo "[$i/30] ✓ Server process is running!"
  else
    echo "[$i/30] ✗ Server process not found"
  fi
  sleep 1
done

echo ""
echo "[5/5] Final status check..."
echo ""
echo "=== CONTAINER STATUS ==="
docker ps -a | grep asa-fixed-test

echo ""
echo "=== LAST 50 LINES OF LOGS ==="
docker logs --tail 50 asa-fixed-test

echo ""
echo "========================================="
echo "Test complete! Review the output above."
echo "To view full logs: docker logs asa-fixed-test"
echo "To stop test: docker stop asa-fixed-test && docker rm asa-fixed-test"
echo "========================================="